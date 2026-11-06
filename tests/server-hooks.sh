#!/usr/bin/env bash
# The server module's post-packages hook: it refuses an apply that would lock the user out of ssh. Run it inside
# the sandbox image; it needs sudo (the image's ubuntu user has it without a password) and bash.
# usage: tests/server-hooks.sh
#
# Contract
#   - No key in ~/.ssh/authorized_keys (missing file, empty file, only comments) exits 1 and names the file.
#   - A key line in authorized_keys or authorized_keys2 exits 0.
#   - DJD_SKIP_SSH_CHECKS=1 exits 0 without a key.
#   - A Port other than 22 in sshd_config.d exits 1; Port 22 exits 0.
#   - Running as root exits 1: the module turns root login off.
#
# The hook is run for real. The only change to the machine is the docker group the hook adds the user to, and a
# drop-in under /etc/ssh/sshd_config.d that this script removes again.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
hook=$here/../mise-config/hooks/server-post-packages
work=$(mktemp -d)
dropin=/etc/ssh/sshd_config.d/99-djd-test.conf
cleanup() {
    sudo rm -f "$dropin"
    rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "server-hooks: $1" >&2
    exit 1
}

# the hook adds the user to docker, which a machine with the server module has (docker.io creates the group)
if ! getent group docker >/dev/null; then sudo groupadd docker; fi
sudo install -d /etc/ssh/sshd_config.d

# run [VAR=value...]: sets rc and $work/err; $HOME is $work/home
rc=0
run() {
    rc=0
    env HOME="$work/home" "$@" bash "$hook" >"$work/out" 2>"$work/err" || rc=$?
}
want_rc() { [ "$rc" = "$2" ] || fail "$1: exit $rc, want $2: $(cat "$work/err")"; }
want_err() { grep -q -- "$2" "$work/err" || fail "$1: stderr lacks '$2': $(cat "$work/err")"; }

mkdir -p "$work/home/.ssh"
run
want_rc "no authorized_keys" 1
want_err "no authorized_keys" authorized_keys
: >"$work/home/.ssh/authorized_keys"
run
want_rc "empty authorized_keys" 1
printf '# a comment\n\n' >"$work/home/.ssh/authorized_keys"
run
want_rc "only comments" 1
run DJD_SKIP_SSH_CHECKS=1
want_rc "check skipped" 0

printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK test@example\n' >"$work/home/.ssh/authorized_keys"
run
want_rc "a key in authorized_keys" 0
rm "$work/home/.ssh/authorized_keys"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK test@example\n' >"$work/home/.ssh/authorized_keys2"
run
want_rc "a key in authorized_keys2" 0
mv "$work/home/.ssh/authorized_keys2" "$work/home/.ssh/authorized_keys"

printf 'Port 22\n' | sudo tee "$dropin" >/dev/null
run
want_rc "Port 22" 0
printf 'Port 2222\n' | sudo tee "$dropin" >/dev/null
run
want_rc "Port 2222" 1
want_err "Port 2222" "other than 22"
sudo rm -f "$dropin"

# as root, with a key: the root-login rule alone refuses it
rc=0
# shellcheck disable=SC2024 # sudo runs the hook only; the redirects are meant to write as this user
sudo env HOME="$work/home" bash "$hook" >"$work/out" 2>"$work/err" || rc=$?
want_rc "root" 1
want_err "root" "normal user"

echo "server-hooks: ok"
