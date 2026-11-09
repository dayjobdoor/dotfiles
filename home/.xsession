#!/bin/sh
# No logind in the Docker image, so nothing else sets it; the PipeWire socket lives there.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# The desktop session is Japanese, and nothing else is: /etc/locale.conf stays C.UTF-8, so ssh logins, agents and the
# Docker image keep English tool output. language-pack-ja-base generates this locale.
export LANG=ja_JP.UTF-8
# GTK, Qt and XIM clients reach fcitx5 through these.
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
# sesman's environment may carry the address of a dead bus; neither dbus-launch nor the daemons may see it.
unset DBUS_SESSION_BUS_ADDRESS
# The audio daemons start inside the session's own bus: with DISPLAY set and no bus each would autolaunch a bus of
# its own. The desktop does not wait for them. pw-cli asks the server instead of testing for the socket file: that
# skips a systemd user manager's already-running socket-activated server (a VM) and ignores the stale socket a
# restarted container keeps in /run. A server that already answered is not ours and stays running at logout.
# startxfce4 runs without exec so that the shell outlives it and ends what this script started: with an exec,
# logging out would leave pipewire, pipewire-pulse and the supervisor running, and the supervisor would start a
# wireplumber against the dead bus. A session that only disconnects keeps startxfce4 running, so nothing is killed.
# shellcheck disable=SC2016 # the inner sh must expand $(seq 600) and the rest, this one must not
exec dbus-launch --exit-with-session sh -c '
server= supervisor=
if command -v pipewire >/dev/null && ! pw-cli info 0 >/dev/null 2>&1; then
    pipewire &
    server=$!
    (
        pulse=
        # TERM can arrive before a PID is saved, so the kill list names $! as well as $pulse
        stop() {
            kill $pulse $! 2>/dev/null
            exit 0
        }
        trap stop TERM
        # wireplumber exits with "Failed to connect to PipeWire" if it starts before the server answers
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
        # wireplumber starts again when it dies while the server answers; five runs in a row under 30 s end the loop
        quick=0
        while [ "$quick" -lt 5 ] && pw-cli info 0 >/dev/null 2>&1; do
            started=$(date +%s)
            wireplumber &
            wait $!
            if [ $(($(date +%s) - started)) -ge 30 ]; then quick=0; else quick=$((quick + 1)); fi
            # back-off, so a wireplumber that dies at once is not started again in a tight loop
            sleep 1
        done
    ) &
    supervisor=$!
fi
startxfce4
status=$?
kill $supervisor $server 2>/dev/null
exit $status'
