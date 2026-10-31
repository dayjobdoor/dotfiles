#!/usr/bin/env bash
# The desktop module's four required apps, as the desktop user in the image (mise-tasks/test/desktop) or the VM
# (tests/vm-checks.sh): the command runs and the XFCE menu entry points at something executable.
# DJD_APPS_LAUNCH=1 (the image test only) also starts brave-browser and zen headless; zed and ghostty need a
# display, so they keep the checks above.
set -euo pipefail

# command|desktop file id
apps='brave-browser|brave-browser
ghostty|com.mitchellh.ghostty
zen|zen
zed|dev.zed.Zed'

# a login shell's PATH is not guaranteed in docker exec or ssh
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
dirs=("${XDG_DATA_HOME:-$HOME/.local/share}" /usr/local/share /usr/share)
launch=${DJD_APPS_LAUNCH:-}
if [ "$launch" = 1 ]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
fi

fail() {
    echo "desktop-apps: $1" >&2
    exit 1
}

# the main group's Exec; the [Desktop Action] groups below it carry their own
main_exec() {
    awk '/^\[/ { in_main = ($0 == "[Desktop Entry]") } in_main && sub(/^Exec=/, "") { print; exit }' "$1"
}

# run_headless APP CMD...: CMD exits 0 within 90s, its stdout lands in $tmp/APP.out
run_headless() {
    local app=$1 rc=0
    shift
    timeout 90 "$@" >"$tmp/$app.out" 2>"$tmp/$app.err" || rc=$?
    [ "$rc" = 0 ] || fail "$app does not launch (exit $rc, 124 is the 90s timeout): $(tail -n 5 "$tmp/$app.err")"
}

# Runs the effective entry's Exec as written: the image's user-level one carries --no-sandbox. The
# brave-browser-stable wrapper exits 0 when Brave aborts, so the dumped DOM is the proof, not the exit code.
launch_brave() {
    local words
    read -ra words <<<"$(main_exec "$1" | sed -E 's/%[A-Za-z]//g')"
    run_headless brave-browser "${words[@]}" --headless=new --disable-gpu --dump-dom about:blank
    grep -q '<html' "$tmp/brave-browser.out" || fail "brave-browser --dump-dom printed no <html: $(tail -n 5 "$tmp/brave-browser.err")"
    echo "ok brave-browser launches"
}

launch_zen() {
    run_headless zen zen --headless --screenshot "$tmp/zen.png" about:blank
    [ -s "$tmp/zen.png" ] || fail "zen wrote no screenshot"
    [ "$(head -c 4 "$tmp/zen.png" | tail -c 3)" = PNG ] || fail "zen's screenshot is not a PNG"
    echo "ok zen launches"
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
    # first word of the main Exec; field codes such as %U come after it
    exec_cmd=$(main_exec "$entry")
    exec_cmd=${exec_cmd%% *}
    if ! command -v "$exec_cmd" >/dev/null; then fail "$entry: Exec '$exec_cmd' is not executable"; fi
    echo "ok $cmd"
    if [ "$launch" = 1 ]; then
        case $cmd in
        brave-browser) launch_brave "$entry" ;;
        zen) launch_zen ;;
        esac
    fi
done <<<"$apps"
