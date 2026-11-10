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
#   - The result does not depend on the machine's git: a global excludesfile named in the git config, or the
#     default ~/.config/git/ignore, hides nothing and adds nothing. Both are planted here and tree.sh must ignore
#     them, so deleting a rule from the repository's .gitignore makes this test fail.
#   - A tracked file that was deleted from the worktree is skipped instead of making tar fail.
#   - A nested git repository, whether untracked or staged as a submodule entry, is left out whole: git lists it as one
#     directory, and tar would read its ignored files (.env, age.txt) and its .git without the outer .gitignore.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo=$work/repo

fail() {
    echo "tree-check: $1" >&2
    exit 1
}

# The setup runs in an empty HOME with no global git config, so the machine's own ignore file cannot reach it.
# (Ours ignores .env and .env.*, which would hide a missing rule of the repository's .gitignore.)
export HOME=$work/home GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME
mkdir -p "$HOME/.config/git"
mkdir -p "$repo/tests" "$repo/mise-config" "$repo/.devcontainer" "$repo/gh" "$repo/rclone"
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
echo secret >.env.production
echo secret >.vars
echo secret >token.local
echo secret >gh/hosts.yml
echo secret >rclone/rclone.conf
echo secret >auth.json
echo secret >key.pem
echo secret >id.key
mkdir nested sub
git -C nested init -q
echo secret >nested/.env
echo secret >nested/age.txt
git -C sub init -q
git -C sub -c user.name=t -c user.email=t@localhost commit -q --allow-empty -m sub
echo secret >sub/.env
git add sub 2>/dev/null

# A hostile machine, planted after the commit so that the setup above is not affected: *.txt is ignored by the
# default file (~/.config/git/ignore) and, for the second run, by an excludesfile named in the git config. Neither
# may change the archive. Without this, tree.sh passes here on a machine whose own ignore file hides the same files.
echo '*.txt' >"$HOME/.config/git/ignore"
cp "$HOME/.config/git/ignore" "$HOME/hostile-ignore"
printf '[core]\n\texcludesFile = %s\n' "$HOME/hostile-ignore" >"$HOME/hostile.gitconfig"

check_archive() {
    local label=$1 want unwanted
    list=$(tests/tree.sh | tar -tf -) || fail "$label: tree.sh failed or its output is not a tar archive"
    for want in tracked.txt new.txt "with space.txt" dangling .gitignore tests/tree.sh; do
        grep -qxF -- "$want" <<<"$list" || fail "$label: $want is missing from the archive:
$list"
    done
    for unwanted in age.txt .env .devcontainer/.env mise-config/miserc.local.toml mise-config/config.local.toml .secrets .env.production .vars token.local gh/hosts.yml rclone/rclone.conf auth.json key.pem id.key gone.txt nested/.env nested/age.txt nested/.git/config sub sub/.env; do
        if grep -qxF -- "$unwanted" <<<"$list"; then fail "$label: $unwanted is in the archive"; fi
    done
}
check_archive "default ignore file"
GIT_CONFIG_GLOBAL=$HOME/hostile.gitconfig check_archive "excludesfile in the git config"
echo "ok tree.sh archive"
