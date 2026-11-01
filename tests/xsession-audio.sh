#!/usr/bin/env bash
# How ~/.xsession starts the audio daemons, against stub binaries: the real script, fake pipewire, pw-cli, wireplumber,
# pipewire-pulse and startxfce4, so no PipeWire and no display are needed. Timing is a stub's sleep.
# usage: tests/xsession-audio.sh [XSESSION]    default: desktop/.xsession next to this directory
#
# Contract
#   - The desktop starts without waiting for the audio server, however slow it is.
#   - wireplumber starts after the server answers, and starts again after it dies while the server still runs.
#   - A server that already answers (a VM's socket-activated one) gets no second server and no second wireplumber.
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

# Every stub appends its PID to $state/pids, so the cleanup kills those and nothing else. A stub that has exec'd
# `sleep` keeps its PID. The supervisor loop in the script ends when its server stops answering, which the removal
# of $state/up causes.
cleanup() {
    [ -z "$root" ] && return 0
    rm -f "$state/up"
    if [ -f "$state/pids" ]; then
        # shellcheck disable=SC2046 # one PID per line, no spaces
        kill $(cat "$state/pids") 2>/dev/null || true
    fi
    rm -rf "$root"
    root='' state=''
}
trap cleanup EXIT

setup() {
    root=$(mktemp -d)
    state=$root/state
    mkdir -p "$root/bin" "$root/rt" "$state"
    : >"$state/log"

    cat >"$root/bin/dbus-launch" <<'EOF'
#!/bin/sh
[ "$1" = --exit-with-session ] && shift
exec "$@"
EOF
    cat >"$root/bin/pipewire" <<'EOF'
#!/bin/sh
echo $$ >>"$STATE/pids"
echo "pipewire starts" >>"$STATE/log"
sleep "$PW_DELAY"
: >"$STATE/up"
echo "pipewire answers" >>"$STATE/log"
exec sleep 600
EOF
    cat >"$root/bin/pw-cli" <<'EOF'
#!/bin/sh
[ -e "$STATE/up" ]
EOF
    cat >"$root/bin/wireplumber" <<'EOF'
#!/bin/sh
if [ -e "$STATE/up" ]; then
    echo $$ >"$STATE/wp.pid"
    echo $$ >>"$STATE/pids"
    echo "wireplumber connects" >>"$STATE/log"
    [ -e "$STATE/crash" ] && exit 1
    exec sleep 600
fi
echo "wireplumber fails: no server" >>"$STATE/log"
exit 1
EOF
    cat >"$root/bin/pipewire-pulse" <<'EOF'
#!/bin/sh
echo $$ >>"$STATE/pids"
echo "pipewire-pulse starts" >>"$STATE/log"
exec sleep 600
EOF
    cat >"$root/bin/startxfce4" <<'EOF'
#!/bin/sh
echo "desktop starts" >>"$STATE/log"
EOF
    chmod +x "$root"/bin/*
}

# runs the script as a login does; $1 is how long the stub server needs to answer
login() {
    env -i PATH="$root/bin:/usr/bin:/bin" HOME="$root" XDG_RUNTIME_DIR="$root/rt" STATE="$state" PW_DELAY="$1" \
        sh "$script" >"$root/out" 2>&1 || fail "the script exited non-zero: $(cat "$root/out")"
}

echo "== a slow server does not hold the desktop back"
setup
# slower than the 5 s the first fix waited, so a script that still waits gives up before the server answers
started=$(date +%s)
login 7
elapsed=$(($(date +%s) - started))
[ "$elapsed" -le 2 ] || fail "the script took $elapsed s to reach the desktop: it waits for the audio server"
logged 'desktop starts' || fail "the desktop did not start"
server_up && fail "the stub server answered before the desktop started, so the scenario proves nothing"
wait_for 12 server_up || fail "the stub server never answered"
wait_for 8 connected 1 || fail "wireplumber never connected after the server answered (it gave up waiting)"
wait_for 5 logged 'pipewire-pulse starts' || fail "pipewire-pulse never started"
[ "$(count 'wireplumber fails')" = 0 ] || fail "wireplumber started before the server answered"
echo "ok desktop first, wireplumber and pipewire-pulse after the server answers"

echo "== wireplumber is started again after it dies"
wait_for 2 test -s "$state/wp.pid" || fail "no wireplumber PID recorded"
kill "$(cat "$state/wp.pid")"
wait_for 10 connected 2 || fail "wireplumber was not started again within 10 s of dying"
echo "ok wireplumber respawns while the server runs"
cleanup

echo "== a wireplumber that keeps dying is given up on"
setup
: >"$state/crash"
login 0
wait_for 12 connected 5 || fail "wireplumber was not started five times"
sleep 3
[ "$(count 'wireplumber connects')" = 5 ] || fail "wireplumber was started $(count 'wireplumber connects') times, not given up on after five"
echo "ok the supervisor gives up after five quick deaths"
cleanup

echo "== a server that already answers gets nothing started"
setup
: >"$state/up"
login 0
wait_for 2 logged 'desktop starts' || fail "the desktop did not start"
sleep 1
[ "$(count 'pipewire starts')" = 0 ] || fail "a second server was started"
[ "$(count 'wireplumber connects')" = 0 ] || fail "wireplumber was started next to an already running server"
echo "ok existing server left alone"
