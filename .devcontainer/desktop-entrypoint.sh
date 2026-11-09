#!/usr/bin/env bash
# Entrypoint of the image for its desktop (runs as root): set the RDP password, make this container's TLS key, then run xrdp in the
# foreground.
# Usage: djd-desktop-entrypoint USER [PASSWORD]
# Without PASSWORD the password is read from /run/secrets/djd_rdp_password, which compose.yaml mounts: an argument
# shows in `docker inspect` and in /proc/1/cmdline, a mounted secret does not.
set -euo pipefail

die() {
    echo "djd-desktop-entrypoint: $*" >&2
    exit 2
}
user=${1:-dayjobdoor}
password=${2:-}
secret=/run/secrets/djd_rdp_password
if [ -z "$password" ] && [ -f "$secret" ]; then password=$(<"$secret"); fi
[[ $user =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid user: $user"
id "$user" >/dev/null 2>&1 || die "no such user: $user"
[ -n "$password" ] || die "usage: djd-desktop-entrypoint USER [PASSWORD]; with no PASSWORD, $secret must hold a non-empty one"
# chpasswd reads one user:password pair per line: a newline in the password would set another account's password
[[ $password != *$'\n'* ]] || die "the password must not contain a newline"

printf '%s:%s\n' "$user" "$password" | chpasswd
# no logind in the container: this is the XDG_RUNTIME_DIR that ~/.xsession falls back to
install -d -m 700 -o "$user" -g "$user" "/run/user/$(id -u "$user")"
# /run survives a container restart, and a stale pid file makes xrdp and sesman refuse to start
rm -f /var/run/xrdp*.pid /var/run/xrdp/*.pid
# /etc/xrdp/{cert,key}.pem link to the snakeoil pair that ssl-cert made once, while the image was built: every
# container of the image would share a key that anyone who pulls the image holds. The files keep their owner and mode.
make-ssl-cert generate-default-snakeoil --force-overwrite

# exec: xrdp replaces the shell and gets docker stop's SIGTERM (directly as PID 1 under a plain docker run, from
# docker-init under compose's init: true); the daemonized sesman goes down with the container
xrdp-sesman
exec xrdp --nodaemon
