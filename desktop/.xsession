#!/bin/sh
# No logind in the Docker image, so nothing else sets it; the PipeWire socket lives there.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# GTK, Qt and XIM clients reach fcitx5 through these.
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
# sesman's environment may carry the address of a dead bus; neither dbus-launch nor the daemons may see it.
unset DBUS_SESSION_BUS_ADDRESS
# The audio daemons start inside the session's own bus: with DISPLAY set and no bus each would autolaunch a bus of
# its own. The desktop does not wait for them. A background shell waits for pipewire to answer (600 polls 0.1 s
# apart), because wireplumber exits with "Failed to connect to PipeWire" when it starts first, then starts
# pipewire-pulse and keeps wireplumber running: it starts it again when it dies, and gives up after five runs in a
# row that each lasted under 30 s.
# Asking the server (not testing for the socket file) skips a systemd user manager's already-running socket-activated
# server (a VM) and ignores the stale socket a restarted container keeps in /run.
# startxfce4 runs without exec so that the shell outlives it and ends what this script started: logging out leaves
# pipewire, pipewire-pulse and the supervisor running, and the supervisor would start a wireplumber against the dead
# bus. The supervisor ends its own wireplumber and pipewire-pulse on TERM; its kill list names $! because TERM can
# arrive between starting a daemon and saving its PID. A session that only disconnects keeps startxfce4 running, so
# nothing is killed. A server that already answered is not ours and stays.
# shellcheck disable=SC2016 # the inner sh must expand $(seq 600) and the rest, this one must not
exec dbus-launch --exit-with-session sh -c '
server= supervisor=
if command -v pipewire >/dev/null && ! pw-cli info 0 >/dev/null 2>&1; then
    pipewire &
    server=$!
    (
        pulse=
        stop() {
            kill $pulse $! 2>/dev/null
            exit 0
        }
        trap stop TERM
        for _ in $(seq 600); do
            pw-cli info 0 >/dev/null 2>&1 && break
            sleep 0.1
        done
        if ! pw-cli info 0 >/dev/null 2>&1; then
            echo "xsession: pipewire did not answer after 600 polls, so wireplumber and pipewire-pulse stay off" >&2
            exit 0
        fi
        pipewire-pulse &
        pulse=$!
        quick=0
        while [ "$quick" -lt 5 ] && pw-cli info 0 >/dev/null 2>&1; do
            started=$(date +%s)
            wireplumber &
            wait $!
            if [ $(($(date +%s) - started)) -ge 30 ]; then quick=0; else quick=$((quick + 1)); fi
            sleep 1
        done
    ) &
    supervisor=$!
fi
startxfce4
status=$?
kill $supervisor $server 2>/dev/null
exit $status'
