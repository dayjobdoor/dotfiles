#!/usr/bin/env bash
# The desktop's four required apps, as the desktop user in the image (.mise/tasks/test/desktop) or the VM
# (tests/vm-checks.sh): the command runs and the XFCE menu entry points at something executable. The extra apps
# (Wireshark, Obsidian, Vicinae, Ferdium) only have to be on PATH with a menu entry that points at something
# executable, and fusuma, a gem that has no menu entry, on PATH; Electron programs print no version without a
# display, so they are not run.
# DJD_APPS_LAUNCH=1 (the image test only, which runs it after the RDP login) also starts brave-browser and zen headless,
# and ghostty and zed inside the running XFCE session, where each must put a window on screen.
set -euo pipefail

# command|desktop file id
apps='brave-browser|brave-browser
ghostty|com.mitchellh.ghostty
zen|zen
zed|dev.zed.Zed'

# command|desktop file id (empty for none)|argument that prints a version (empty for none)
extras='wireshark|org.wireshark.Wireshark|--version
obsidian|obsidian|
vicinae|vicinae|version
ferdium|ferdium|
fusuma||'

# docker exec and a non-login ssh command get no profile PATH: add the mise shims
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
    timeout 90 "$@" >"$tmp/$app.out" 2>"$tmp/$app.err" </dev/null || rc=$?
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

# windows_of CLASS: ids of the visible windows of WM_CLASS CLASS, one per line (exit 1 from xdotool is "none").
# Uses launch_window's $session and $app. A missing display or XAUTHORITY lands in $tmp/$app.xdotool.
windows_of() {
    env "${session[@]}" xdotool search --onlyvisible --class "^${1//./\\.}\$" 2>>"$tmp/$app.xdotool" || true
}

# launch_window APP CLASS ENTRY: ENTRY's Exec runs with the DISPLAY, XAUTHORITY and D-Bus address of the running
# xfce4-session (what a menu click inherits), and a visible window of WM_CLASS CLASS that was not there before the
# launch must appear within 30s: a window left over from an earlier launch does not count.
launch_window() {
    local app=$1 class=$2 words sid win='' pid='' launcher start elapsed
    local -a session
    read -ra words <<<"$(main_exec "$3" | sed -E 's/%[A-Za-z]//g')"
    sid=$(pgrep -o -u "$(id -u)" -x xfce4-session) || fail "$app: no xfce4-session to show a window in"
    mapfile -t session < <(tr '\0' '\n' <"/proc/$sid/environ" | grep -E '^(DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS)=' || true)
    printf '%s\n' "${session[@]}" | grep -q '^DISPLAY=' || fail "$app: xfce4-session has no DISPLAY"
    windows_of "$class" >"$tmp/$app.before"
    start=$SECONDS
    env "${session[@]}" setsid timeout 60 "${words[@]}" >"$tmp/$app.out" 2>"$tmp/$app.err" </dev/null &
    launcher=$!
    for _ in $(seq 30); do
        win=$(windows_of "$class" | grep -vxFf "$tmp/$app.before" | head -n1 || true)
        [ -z "$win" ] || break
        sleep 1
    done
    elapsed=$((SECONDS - start))
    [ -z "$win" ] || pid=$(env "${session[@]}" xdotool getwindowpid "$win" 2>>"$tmp/$app.xdotool" || true)
    # zed-editor leaves the launcher's session for its own, so the window's process is signalled too
    kill -TERM -- "-$launcher" ${pid:+"$pid"} 2>/dev/null || true
    [ -n "$win" ] || fail "$app showed no $class window in ${elapsed}s: $(tail -n 5 "$tmp/$app.err") xdotool: $(tail -n 3 "$tmp/$app.xdotool")"
    [ -n "$pid" ] || fail "$app's window has no _NET_WM_PID, so the app cannot be stopped: $(tail -n 3 "$tmp/$app.xdotool")"
    for _ in $(seq 20); do
        if ! kill -0 "$pid" 2>/dev/null && ! pgrep -g "$launcher" >/dev/null; then break; fi
        sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null || pgrep -g "$launcher" >/dev/null; then
        kill -KILL -- "-$launcher" "$pid" 2>/dev/null || true
        fail "$app (pid $pid) is still running after SIGTERM"
    fi
    echo "ok $app window (after ${elapsed}s)"
}

checked=0
while IFS='|' read -r cmd id; do
    command -v "$cmd" >/dev/null || fail "$cmd is not on PATH"
    # shims print their own error for a tool that is not installed, and exit non-zero; stdin is the app list
    if ! "$cmd" --version >/dev/null 2>&1 </dev/null; then fail "$cmd --version failed"; fi

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
        ghostty) launch_window ghostty com.mitchellh.ghostty "$entry" ;;
        zen) launch_zen ;;
        zed) launch_window zed dev.zed.Zed "$entry" ;;
        esac
    fi
    checked=$((checked + 1))
done <<<"$apps"
# a launched command that swallowed the list would end the loop early without a failure
[ "$checked" = "$(grep -c . <<<"$apps")" ] || fail "checked $checked apps, the list has $(grep -c . <<<"$apps")"

extra_checked=0
while IFS='|' read -r cmd id version; do
    command -v "$cmd" >/dev/null || fail "$cmd is not on PATH"
    if [ -n "$version" ] && ! "$cmd" "$version" >/dev/null 2>&1 </dev/null; then fail "$cmd $version failed"; fi
    if [ -n "$id" ]; then
        entry=
        for d in "${dirs[@]}"; do
            if [ -f "$d/applications/$id.desktop" ]; then
                entry="$d/applications/$id.desktop"
                break
            fi
        done
        [ -n "$entry" ] || fail "$cmd has no $id.desktop menu entry"
        exec_cmd=$(main_exec "$entry")
        exec_cmd=${exec_cmd%% *}
        if ! command -v "$exec_cmd" >/dev/null; then fail "$entry: Exec '$exec_cmd' is not executable"; fi
    fi
    echo "ok $cmd"
    extra_checked=$((extra_checked + 1))
done <<<"$extras"
[ "$extra_checked" = "$(grep -c . <<<"$extras")" ] || fail "checked $extra_checked extra apps, the list has $(grep -c . <<<"$extras")"
