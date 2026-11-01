#!/bin/sh
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
unset DBUS_SESSION_BUS_ADDRESS
# The audio daemons start inside the session's own bus: with DISPLAY set and no bus each would autolaunch a bus of
# its own. The desktop does not wait for them. A background shell waits for pipewire to answer, because wireplumber
# exits with "Failed to connect to PipeWire" when it starts first, then starts pipewire-pulse and keeps wireplumber
# running: it starts it again when it dies, and gives up after five runs in a row that each lasted under 30 s.
# Asking the server (not testing for the socket file) skips a systemd user manager's already-running socket-activated
# server (a VM) and ignores the stale socket a restarted container keeps in /run.
# shellcheck disable=SC2016 # the inner sh must expand $(seq 600) and the rest, this one must not
exec dbus-launch --exit-with-session sh -c '
if command -v pipewire >/dev/null && ! pw-cli info 0 >/dev/null 2>&1; then
    pipewire &
    (
        for _ in $(seq 600); do
            pw-cli info 0 >/dev/null 2>&1 && break
            sleep 0.1
        done
        if ! pw-cli info 0 >/dev/null 2>&1; then
            echo "xsession: pipewire did not answer within 60 s, so wireplumber and pipewire-pulse stay off" >&2
            exit 0
        fi
        pipewire-pulse &
        quick=0
        while [ "$quick" -lt 5 ] && pw-cli info 0 >/dev/null 2>&1; do
            started=$(date +%s)
            wireplumber
            if [ $(($(date +%s) - started)) -ge 30 ]; then quick=0; else quick=$((quick + 1)); fi
            sleep 1
        done
    ) &
fi
exec startxfce4'
