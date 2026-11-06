#!/usr/bin/env bash
# What tests/tree.sh puts in the archive, run on a copy of the script inside a throwaway git repository.
# Needs bash, coreutils, git and tar. usage: tests/tree-check.sh
#
# Contract
#   - Tracked and untracked-but-unignored files are in the archive, a dangling symlink and a name with a space
#     included.
#   - Files that the repository's own .gitignore lists (age.txt, .env files, *.local.toml, .secrets, credential
#     files) are not, while they are untracked: they must never reach a container, a VM or act. A file that was
#     force-added is tracked, and tree.sh sends it; gitleaks is what stops that one.
#   - The result does not depend on the git configuration of the machine that runs it (a global excludesfile).
#   - A tracked file that was deleted from the worktree is skipped instead of making tar fail.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo=$work/repo

fail() {
    echo "tree-check: $1" >&2
    exit 1
}

# a global excludesfile (ours ignores *.env) would hide a missing rule of the repository's own .gitignore
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$repo/tests" "$repo/mise-config" "$repo/.devcontainer"
cp "$here/tree.sh" "$repo/tests/tree.sh"
cp "$here/../.gitignore" "$repo/.gitignore"
cd "$repo"
git init -q
echo x >tracked.txt
echo x >gone.txt
echo x >"with space.txt"
ln -s nowhere dangling
git add -A
git -c user.name=t -c user.email=t@localhost commit -qm base
rm gone.txt
echo x >new.txt
echo secret >age.txt
echo secret >.env
echo secret >.devcontainer/.env
echo secret >mise-config/miserc.local.toml
echo secret >mise-config/config.local.toml
echo secret >.secrets
echo secret >.env.local
echo secret >key.pem

list=$(tests/tree.sh | tar -tf -) || fail "tree.sh failed or its output is not a tar archive"
for want in tracked.txt new.txt "with space.txt" dangling .gitignore tests/tree.sh; do
    grep -qxF -- "$want" <<<"$list" || fail "$want is missing from the archive:
$list"
done
for unwanted in age.txt .env .devcontainer/.env mise-config/miserc.local.toml mise-config/config.local.toml .secrets .env.local key.pem gone.txt; do
    if grep -qxF -- "$unwanted" <<<"$list"; then fail "$unwanted is in the archive"; fi
done
echo "ok tree.sh archive"
