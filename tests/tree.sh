#!/usr/bin/env bash
# Streams the tracked and unignored files of this checkout as a tar archive, for `docker run -i`, a VM or act.
# .devcontainer/.env, age.txt and miserc.local.toml stay behind because they are ignored. git still lists a
# file that was deleted but not yet staged, and tar fails on it, so it is skipped here.
# Only the repository's own .gitignore decides: the git config of the machine and its global ignore file would
# otherwise change what a container, a VM or act receives. GIT_CONFIG_GLOBAL and GIT_CONFIG_NOSYSTEM drop the
# config files; core.excludesFile=/dev/null covers the file git reads without any config (~/.config/git/ignore).
# COPYFILE_DISABLE and --no-xattrs are for a macOS host: its tar adds AppleDouble ._* entries and extended
# attributes that GNU tar in the container would extract as stray files.
set -euo pipefail
cd "$(dirname "$0")/.."

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git -c core.excludesFile=/dev/null ls-files -z -co --exclude-standard | while IFS= read -r -d '' f; do
    if [ -e "$f" ] || [ -L "$f" ]; then printf '%s\0' "$f"; fi
done | COPYFILE_DISABLE=1 tar --no-xattrs --null -T - -cf -
