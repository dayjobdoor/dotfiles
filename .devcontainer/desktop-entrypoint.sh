#!/usr/bin/env bash
# Desktop image entrypoint (runs as root): set the RDP password, then run xrdp in the foreground.
# Usage: djd-desktop-entrypoint USER PASSWORD
set -euo pipefail

die() {
    echo "djd-desktop-entrypoint: $*" >&2
    exit 2
}
user=${1:-ubuntu}
password=${2:-}
[[ $user =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid user: $user"
id "$user" >/dev/null 2>&1 || die "no such user: $user"
[ -n "$password" ] || die "usage: djd-desktop-entrypoint USER PASSWORD"

printf '%s:%s\n' "$user" "$password" | chpasswd
install -d -m 700 -o "$user" -g "$user" "/run/user/$(id -u "$user")"
rm -f /var/run/xrdp*.pid /var/run/xrdp/*.pid

# exec: xrdp becomes PID 1 and gets docker stop's SIGTERM; the daemonized sesman goes down with the container
xrdp-sesman
exec xrdp --nodaemon
