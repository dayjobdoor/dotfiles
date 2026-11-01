#!/usr/bin/env bash
# What tests/tree.sh puts in the archive, run on a copy of the script inside a throwaway git repository.
# Needs bash, coreutils, git and tar. usage: tests/tree-check.sh
#
# Contract
#   - Tracked and untracked-but-unignored files are in the archive, a dangling symlink and a name with a space
#     included.
#   - Ignored files (age.txt, .env files, *.local.toml) are not: they must never reach a container, a VM or act.
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

mkdir -p "$repo/tests" "$repo/mise-config" "$repo/.devcontainer"
cp "$here/tree.sh" "$repo/tests/tree.sh"
cd "$repo"
git init -q
printf 'age.txt\n.env\n*.local.toml\n' >.gitignore
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

list=$(tests/tree.sh | tar -tf -) || fail "tree.sh failed or its output is not a tar archive"
for want in tracked.txt new.txt "with space.txt" dangling .gitignore tests/tree.sh; do
    grep -qxF -- "$want" <<<"$list" || fail "$want is missing from the archive:
$list"
done
for unwanted in age.txt .env .devcontainer/.env mise-config/miserc.local.toml gone.txt; do
    if grep -qxF -- "$unwanted" <<<"$list"; then fail "$unwanted is in the archive"; fi
done
echo "ok tree.sh archive"
