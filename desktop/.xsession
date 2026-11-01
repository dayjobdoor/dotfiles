#!/bin/sh
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
# A systemd user manager (a VM) has already opened the PipeWire socket. Without one (the Docker image) nothing
# starts the audio stack, and the xrdp sink has no server to attach to.
if [ ! -S "$XDG_RUNTIME_DIR/pipewire-0" ]; then
    pipewire &
    wireplumber &
    pipewire-pulse &
fi
unset DBUS_SESSION_BUS_ADDRESS
exec dbus-launch --exit-with-session startxfce4
