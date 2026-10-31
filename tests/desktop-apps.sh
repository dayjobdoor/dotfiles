#!/usr/bin/env bash
# The desktop module's four required apps, as the desktop user in the image (mise-tasks/test/desktop) or the VM
# (tests/vm-checks.sh): the command runs and the XFCE menu entry points at something executable.
set -euo pipefail

# command|desktop file id
apps='brave-browser|brave-browser
ghostty|com.mitchellh.ghostty
zen|zen
zed|dev.zed.Zed'

# a login shell's PATH is not guaranteed in docker exec or ssh
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
dirs=("${XDG_DATA_HOME:-$HOME/.local/share}" /usr/local/share /usr/share)

fail() {
    echo "desktop-apps: $1" >&2
    exit 1
}

while IFS='|' read -r cmd id; do
    command -v "$cmd" >/dev/null || fail "$cmd is not on PATH"
    # shims print their own error for a tool that is not installed, and exit non-zero
    if ! "$cmd" --version >/dev/null 2>&1; then fail "$cmd --version failed"; fi

    entry=
    for d in "${dirs[@]}"; do
        if [ -f "$d/applications/$id.desktop" ]; then
            entry="$d/applications/$id.desktop"
            break
        fi
    done
    [ -n "$entry" ] || fail "$cmd has no $id.desktop menu entry"
    # first Exec line, first word; field codes such as %U come after it
    exec_cmd=$(sed -n 's/^Exec=//p' "$entry" | sed -n 1p)
    exec_cmd=${exec_cmd%% *}
    if ! command -v "$exec_cmd" >/dev/null; then fail "$entry: Exec '$exec_cmd' is not executable"; fi
    echo "ok $cmd"
done <<<"$apps"
