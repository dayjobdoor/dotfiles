#!/bin/sh
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
unset DBUS_SESSION_BUS_ADDRESS
# The audio daemons start inside the session's own bus: with DISPLAY set and no bus each would autolaunch a bus of
# its own. wireplumber and pipewire-pulse start only once pipewire answers, or wireplumber exits with "Failed to
# connect to PipeWire" and nothing restarts it. Asking the server (not testing for the socket file) skips a systemd
# user manager's already-running socket-activated server (a VM) and ignores the stale socket a restarted container
# keeps in /run.
exec dbus-launch --exit-with-session sh -c '
if command -v pipewire >/dev/null && ! pw-cli info 0 >/dev/null 2>&1; then
    pipewire &
    for _ in $(seq 50); do
        pw-cli info 0 >/dev/null 2>&1 && break
        sleep 0.1
    done
    wireplumber &
    pipewire-pulse &
fi
exec startxfce4'
