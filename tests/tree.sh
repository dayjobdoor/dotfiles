#!/usr/bin/env bash
# Streams the tracked and unignored files of this checkout as a tar archive, for `docker run -i`, a VM or act.
# .devcontainer/.env, age.txt and miserc.local.toml stay behind because they are ignored. git still lists a
# file that was deleted but not yet staged, and tar fails on it, so it is skipped here.
# COPYFILE_DISABLE and --no-xattrs are for a macOS host: its tar adds AppleDouble ._* entries and extended
# attributes that GNU tar in the container would extract as stray files.
set -euo pipefail
cd "$(dirname "$0")/.."

git ls-files -z -co --exclude-standard | while IFS= read -r -d '' f; do
    if [ -e "$f" ] || [ -L "$f" ]; then printf '%s\0' "$f"; fi
done | COPYFILE_DISABLE=1 tar --no-xattrs --null -T - -cf -
