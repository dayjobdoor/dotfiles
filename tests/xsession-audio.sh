#!/usr/bin/env bash
# How ~/.xsession starts and ends the audio daemons, against stub binaries: the real script, fake dbus-launch, pipewire,
# pw-cli, wireplumber, pipewire-pulse, startxfce4, date and (in one scenario) seq, so no PipeWire, bus or display is
# needed. Timing is a stub's sleep. Linux only: leftover processes are found through /proc/PID/environ.
# usage: tests/xsession-audio.sh [XSESSION]    default: desktop/.xsession next to this directory
#
# Contract
#   - The desktop starts without waiting for an audio server that is still starting.
#   - The daemons run on the session's own bus, never on one inherited from the login environment, and the bus is
#     made with --exit-with-session so that it ends with the session.
#   - wireplumber and pipewire-pulse start after the server answers. wireplumber starts again after it dies while the
#     server still runs, and is given up on after five runs in a row that each lasted under 30 s.
#   - When the server never answers, one line goes to stderr (and nothing to stdout), no daemon starts, and the desktop still starts.
#   - A server that already answers (a VM's socket-activated one) gets no second server and no second wireplumber, and
#     is left running when the session ends.
#   - When the desktop exits, every process the script started ends and no wireplumber starts after that. While the
#     desktop runs (a session that only disconnected) nothing ends. The script exits with the desktop's status.
set -euo pipefail

script=$(realpath "${1:-$(dirname "$0")/../desktop/.xsession}")
[ -f "$script" ] || {
    echo "xsession-audio: no such script: $script" >&2
    exit 2
}

root=
state=

fail() {
    echo "xsession-audio: $1" >&2
    [ -z "$state" ] || {
        echo "--- log" >&2
        cat "$state/log" >&2
    }
    exit 1
}

# waits up to $1 seconds for the command in the remaining arguments to succeed
wait_for() {
    local limit=$1
    shift
    for _ in $(seq $((limit * 10))); do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

count() { grep -c -- "$1" "$state/log" || true; }
logged() { grep -q -- "$1" "$state/log"; }
server_up() { [ -e "$state/up" ]; }
connected() { [ "$(count 'wireplumber connects')" -ge "$1" ]; }
exited() { [ -s "$state/rc" ]; }
# every stub and the script's own shells carry STATE=<dir> in their environment
leftovers() { grep -l -a -s -F -- "STATE=$1" /proc/[0-9]*/environ 2>/dev/null | wc -l; }
none_left() { [ "$(leftovers "$1")" -eq 0 ]; }
# The supervisor is the shell that starts wireplumber: the stub records its parent ($PPID). A zombie has ended too.
supervisor_gone() {
    local pid
    pid=$(cat "$state/sup.pid")
    kill -0 "$pid" 2>/dev/null || return 0
    grep -q '^State:[[:space:]]*Z' "/proc/$pid/status" 2>/dev/null
}
all_alive() {
    local pid
    while read -r pid; do kill -0 "$pid" 2>/dev/null || return 1; done <"$state/pids"
}
# the stub bus is the only address a daemon may have seen
daemons_on_session_bus() {
    [ "$(grep ' bus=' "$state/log" | grep -c -v -F -- " bus=unix:path=$state/bus" || true)" = 0 ]
}

# Every stub appends its PID to $state/pids, and the server stub its delay sleep to $state/sleeps, so the cleanup kills
# those and nothing else. A stub that has exec'd `sleep` keeps its PID. The supervisor loop in the script ends when its
# server stops answering, which the removal of $state/up causes, and a held desktop ends with $state/logout.
cleanup() {
    [ -z "$root" ] && return 0
    local dir=$root marker=$state
    rm -f "$state/up"
    : >"$state/logout"
    if [ -f "$state/pids" ]; then
        # shellcheck disable=SC2046 # one PID per line, no spaces
        kill $(cat "$state/pids" "$state/sleeps" 2>/dev/null) 2>/dev/null || true
    fi
    root='' state=''
    if ! wait_for 5 none_left "$marker"; then
        echo "xsession-audio: processes of the script outlived the scenario: $(leftovers "$marker")" >&2
        rm -rf "$dir"
        exit 1
    fi
    rm -rf "$dir"
}
trap cleanup EXIT

setup() {
    root=$(mktemp -d)
    state=$root/state
    mkdir -p "$root/bin" "$root/rt" "$state"
    : >"$state/log"

    cat >"$root/bin/dbus-launch" <<'EOF'
#!/bin/sh
echo "dbus-launch input=${DBUS_SESSION_BUS_ADDRESS:-none}" >>"$STATE/log"
# the session bus must die with the session: without the flag the bus (and the daemons on it) outlive a logout
if [ "$1" != --exit-with-session ]; then
    echo "dbus-launch without --exit-with-session" >>"$STATE/log"
    exit 97
fi
shift
DBUS_SESSION_BUS_ADDRESS=unix:path=$STATE/bus
export DBUS_SESSION_BUS_ADDRESS
exec "$@"
EOF
    cat >"$root/bin/pipewire" <<'EOF'
#!/bin/sh
echo $$ >>"$STATE/pids"
echo "pipewire starts bus=${DBUS_SESSION_BUS_ADDRESS:-none}" >>"$STATE/log"
sleep "$PW_DELAY" &
echo $! >>"$STATE/sleeps"
wait $!
: >"$STATE/up"
echo "pipewire answers" >>"$STATE/log"
exec sleep 600
EOF
    cat >"$root/bin/pw-cli" <<'EOF'
#!/bin/sh
[ -e "$STATE/up" ]
EOF
    # crash: exits at once. long: the third run lasts 30 s by the clock (see date).
    cat >"$root/bin/wireplumber" <<'EOF'
#!/bin/sh
if [ -e "$STATE/up" ]; then
    echo $$ >"$STATE/wp.pid"
    echo $PPID >"$STATE/sup.pid"
    echo $$ >>"$STATE/pids"
    echo "wireplumber connects bus=${DBUS_SESSION_BUS_ADDRESS:-none}" >>"$STATE/log"
    [ -e "$STATE/long" ] && [ "$(grep -c 'wireplumber connects' "$STATE/log")" = 3 ] && echo $(($(cat "$STATE/now") + 30)) >"$STATE/now"
    [ -e "$STATE/crash" ] && exit 1
    exec sleep 600
fi
echo "wireplumber fails: no server" >>"$STATE/log"
exit 1
EOF
    cat >"$root/bin/pipewire-pulse" <<'EOF'
#!/bin/sh
if [ -e "$STATE/up" ]; then server=up; else server=down; fi
echo $$ >>"$STATE/pids"
echo "pipewire-pulse starts server=$server bus=${DBUS_SESSION_BUS_ADDRESS:-none}" >>"$STATE/log"
exec sleep 600
EOF
    cat >"$root/bin/startxfce4" <<'EOF'
#!/bin/sh
echo "desktop starts" >>"$STATE/log"
while [ ! -e "$STATE/logout" ]; do sleep 0.1; done
exit "${DESKTOP_RC:-0}"
EOF
    # the real date, unless $state/now holds a fake clock
    cat >"$root/bin/date" <<'EOF'
#!/bin/sh
[ -e "$STATE/now" ] && exec cat "$STATE/now"
PATH=/usr/bin:/bin
exec date "$@"
EOF
    chmod +x "$root"/bin/*
}

# runs the script as a login does, with a stale bus address in the environment; $1 is how long the stub server needs
# to answer, the rest are further environment variables
run_script() {
    local delay=$1
    shift
    env -i PATH="$root/bin:/usr/bin:/bin" HOME="$root" XDG_RUNTIME_DIR="$root/rt" STATE="$state" PW_DELAY="$delay" \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/stale "$@" sh "$script"
}
# The desktop stub runs until $state/logout exists, so the script is in the background and its exit status lands in
# $state/rc.
login() { (
    set +e
    run_script "$@" >"$root/out" 2>"$root/err"
    echo $? >"$state/rc"
) & }

echo "== a slow server does not hold the desktop back"
setup
# The stub answers after 10 s; reaching the desktop must take at most 2 s, and the poller must outlast the 10 s.
login 10
wait_for 2 logged 'desktop starts' || fail "the desktop did not start within 2 s: the script waits for the audio server"
server_up && fail "the stub server answered before the desktop started, so the scenario proves nothing"
wait_for 15 server_up || fail "the stub server never answered"
wait_for 8 connected 1 || fail "wireplumber never connected after the server answered (it gave up waiting)"
wait_for 5 logged 'pipewire-pulse starts' || fail "pipewire-pulse never started"
[ "$(count 'wireplumber fails')" = 0 ] || fail "wireplumber started before the server answered"
[ "$(count 'pipewire-pulse starts server=down')" = 0 ] || fail "pipewire-pulse started before the server answered"
echo "ok desktop first, wireplumber and pipewire-pulse after the server answers"

echo "== the daemons run on the session's own bus"
logged 'dbus-launch input=none' || fail "dbus-launch inherited a bus address from the login environment"
[ "$(count ' bus=')" -ge 3 ] || fail "fewer than three daemons logged their bus"
daemons_on_session_bus || fail "a daemon ran on a bus other than the one dbus-launch made"
echo "ok no inherited bus, daemons inside the session bus"

echo "== wireplumber is started again after it dies"
wait_for 2 test -s "$state/wp.pid" || fail "no wireplumber PID recorded"
kill "$(cat "$state/wp.pid")"
wait_for 10 connected 2 || fail "wireplumber was not started again within 10 s of dying"
echo "ok wireplumber respawns while the server runs"

echo "== wireplumber is not started again once the server stops answering"
wait_for 2 test -s "$state/wp.pid" || fail "no wireplumber PID recorded"
rm -f "$state/up"
kill "$(cat "$state/wp.pid")"
# the supervisor ends after its back-off, when the server no longer answers; one that kept starting wireplumber would
# log "fails" first (five runs with a back-off each, so the limit is longer than that)
wait_for 10 supervisor_gone || fail "the supervisor was still running 10 s after wireplumber died with no server"
[ "$(count 'wireplumber fails')" = 0 ] || fail "wireplumber was started again although the server no longer answered"
echo "ok the supervisor stops when the server does"
cleanup

echo "== a wireplumber that keeps dying is given up on"
setup
: >"$state/crash"
started=$(date +%s)
login 0
wait_for 12 connected 5 || fail "wireplumber was not started five times"
elapsed=$(($(date +%s) - started))
[ "$elapsed" -ge 4 ] || fail "five wireplumber runs took $elapsed s: no back-off between the runs"
wait_for 5 supervisor_gone || fail "the supervisor was still running 5 s after the fifth quick death"
[ "$(count 'wireplumber connects')" = 5 ] || fail "wireplumber was started $(count 'wireplumber connects') times, not given up on after five"
echo "ok the supervisor gives up after five quick deaths"
cleanup

echo "== a wireplumber that ran 30 s resets the count of quick deaths"
setup
: >"$state/crash"
: >"$state/long"
echo 1000 >"$state/now"
login 0
# runs 1, 2 quick; run 3 lasts 30 s; runs 4 to 8 quick, and five of those end it
wait_for 12 connected 8 || fail "wireplumber was given up on early: a 30 s run did not reset the count"
wait_for 5 supervisor_gone || fail "the supervisor was still running 5 s after the fifth quick death that followed the 30 s run"
[ "$(count 'wireplumber connects')" = 8 ] || fail "wireplumber was started $(count 'wireplumber connects') times, not given up on after five quick deaths following a 30 s run"
echo "ok a long run resets the count"
cleanup

echo "== a server that never answers: one line, no daemon, the desktop starts"
setup
# the poll count is the script's, so a seq of three makes the wait end in 0.3 s
cat >"$root/bin/seq" <<'EOF'
#!/bin/sh
echo 1
echo 2
echo 3
EOF
chmod +x "$root/bin/seq"
login 600
wait_for 2 logged 'desktop starts' || fail "the desktop did not start"
wait_for 5 test -s "$root/err" || fail "the script printed nothing to stderr when the server never answered"
[ "$(wc -l <"$root/err")" -eq 1 ] || fail "expected one line on stderr, got: $(cat "$root/err")"
[ ! -s "$root/out" ] || fail "the script printed to stdout, which a login does not capture: $(cat "$root/out")"
[ "$(count 'pipewire-pulse starts')" = 0 ] || fail "pipewire-pulse started although the server never answered"
[ "$(count 'wireplumber')" = 0 ] || fail "wireplumber started although the server never answered"
echo "ok one line, nothing started"
cleanup

echo "== a server that already answers gets nothing started and is left running"
setup
: >"$state/up"
sleep 600 &
server=$!
echo "$server" >>"$state/pids"
login 0
wait_for 2 logged 'desktop starts' || fail "the desktop did not start"
sleep 1
[ "$(count 'pipewire starts')" = 0 ] || fail "a second server was started"
[ "$(count 'wireplumber connects')" = 0 ] || fail "wireplumber was started next to an already running server"
: >"$state/logout"
wait_for 5 exited || fail "the script did not end after the desktop did"
[ "$(cat "$state/rc")" = 0 ] || fail "the script exited with $(cat "$state/rc")"
kill -0 "$server" 2>/dev/null || fail "the server that was already running was killed when the session ended"
echo "ok existing server left alone"
cleanup

echo "== logging out ends what the script started"
setup
# a held desktop with default stubs, so wireplumber is still running when the session ends
login 0 DESKTOP_RC=3
wait_for 5 connected 1 || fail "wireplumber never connected"
wait_for 5 logged 'pipewire-pulse starts' || fail "pipewire-pulse never started"
sleep 1.5
exited && fail "the script ended while the desktop still ran"
all_alive || fail "a process the script started ended while the desktop still ran"
[ "$(count 'wireplumber connects')" = 1 ] || fail "wireplumber was started again while the desktop ran"
: >"$state/logout"
wait_for 5 exited || fail "the script did not end after the desktop did"
[ "$(cat "$state/rc")" = 3 ] || fail "the script exited with $(cat "$state/rc"), not the desktop's 3"
wait_for 5 none_left "$state" || fail "$(leftovers "$state") processes outlived the session"
# nothing carrying STATE is left, the supervisor included, so nothing can start wireplumber again
[ "$(count 'wireplumber connects')" = 1 ] || fail "wireplumber was started again after the session ended"
echo "ok logout ends the server, the supervisor and its daemons, and nothing respawns"
cleanup
