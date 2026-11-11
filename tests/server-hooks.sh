#!/usr/bin/env bash
# The server module's post-packages hook: it refuses an apply that would lock the user out of ssh. Run it inside
# the image; it needs sudo (the image's dayjobdoor user has it without a password) and bash.
# usage: tests/server-hooks.sh
#
# Contract
#   - No valid key in ~/.ssh/authorized_keys (missing file, empty file, only comments, malformed or truncated) exits 1.
#   - A Port other than 22 in the effective sshd configuration, including an unreadable drop-in, exits 1. An sshd -T
#     failure also exits 1 instead of treating missing output as port 22.
#   - Running as root exits 1: the module turns root login off.
#   - None of those refusals adds the user to the docker group (the hook grants it only after its checks).
#   - A valid key in authorized_keys or authorized_keys2, Port 22, and DJD_SKIP_SSH_CHECKS=1 without a key all exit 0,
#     and each leaves the user in the docker group.
#   - The caller's DJD_SKIP_SSH_CHECKS is dropped from every run but the one that sets it: left in, it would make
#     every "must refuse" case pass without the checks running.
#   - The shared keys-only check accepts the three managed drop-in directives without running sshd, but rejects a
#     corrupted drop-in when sshd -T reports that passwords are enabled.
#
# The hook is run for real. It changes the machine: the docker group (created if missing) and the sshd_config.d
# directory stay; the user's docker membership and a drop-in under /etc/ssh/sshd_config.d are removed again.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
hook=$here/../mise-config/hooks/server-post-packages
keys_only=$here/../mise-config/hooks/sshd-keys-only
work=$(mktemp -d)
dropin=/etc/ssh/sshd_config.d/99-djd-test.conf
managed_dropin=/etc/ssh/sshd_config.d/10-djd.conf
sshd_config=/etc/ssh/sshd_config
sshd_stub=/usr/local/sbin/sshd
config_saved=
stub_created=
me=$(id -un)
cleanup() {
    sudo rm -f "$dropin" "$managed_dropin"
    if [ -n "$config_saved" ]; then sudo cp "$work/sshd_config.orig" "$sshd_config"; else sudo rm -f "$sshd_config"; fi
    if [ -n "$stub_created" ]; then sudo rm -f "$sshd_stub"; fi
    sudo gpasswd -d "$me" docker >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "server-hooks: $1" >&2
    exit 1
}

in_docker() { [[ " $(id -nG "$me") " == *" docker "* ]]; }
want_docker() { in_docker || fail "$1: the hook succeeded but $me is not in the docker group"; }
want_no_docker() { ! in_docker || fail "$1: the hook refused but $me is in the docker group"; }

# the hook adds the user to docker, which a machine with the server module has (docker.io creates the group)
if ! getent group docker >/dev/null; then sudo groupadd docker; fi
sudo install -d /etc/ssh/sshd_config.d
# the membership checks below mean nothing for a user who is in the group already (the image has none)
if in_docker; then fail "$me is already in the docker group; run this in the image (mise run test:offline)"; fi

# run [VAR=value...]: sets rc and $work/err; $HOME is $work/home. -u: see the contract.
rc=0
run() {
    rc=0
    env -u DJD_SKIP_SSH_CHECKS HOME="$work/home" "$@" bash "$hook" >"$work/out" 2>"$work/err" || rc=$?
}
want_rc() { [ "$rc" = "$2" ] || fail "$1: exit $rc, want $2: $(cat "$work/err")"; }
want_err() { grep -q -- "$2" "$work/err" || fail "$1: stderr lacks '$2': $(cat "$work/err")"; }
# refused "label" "message": exit 1, the message, and no docker group
refused() {
    want_rc "$1" 1
    want_err "$1" "$2"
    want_no_docker "$1"
}
# accepted "label": exit 0 and the docker group, which is then taken away again for the next case
accepted() {
    want_rc "$1" 0
    want_docker "$1"
    sudo gpasswd -d "$me" docker >/dev/null
}

mkdir -p "$work/home/.ssh"
run
refused "no authorized_keys" "authorized_keys holds no key"
: >"$work/home/.ssh/authorized_keys"
run
refused "empty authorized_keys" "authorized_keys holds no key"
printf '# a comment\n\n' >"$work/home/.ssh/authorized_keys"
run
refused "only comments" "authorized_keys holds no key"
run DJD_SKIP_SSH_CHECKS=0
refused "DJD_SKIP_SSH_CHECKS=0" "authorized_keys holds no key"
run DJD_SKIP_SSH_CHECKS=1
accepted "check skipped"

printf 'not a public key\n' >"$work/home/.ssh/authorized_keys"
run
refused "malformed authorized_keys" "authorized_keys holds no key"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK test@example\n' >"$work/home/.ssh/authorized_keys"
run
refused "truncated authorized_keys" "authorized_keys holds no key"

key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII3MCP/ibmJg9+H5UXDmNo7tNylEqMB91lcKfpoqXEO9 test@example'
printf '%s\n' "$key" >"$work/home/.ssh/authorized_keys"
echo 22 >"$work/port"
sudo tee "$sshd_stub" >/dev/null <<EOF
#!/bin/sh
[ ! -e "$work/sshd-fail" ] || exit 1
read -r port <"$work/port"
echo "port \$port"
EOF
sudo chmod +x "$sshd_stub"
stub_created=1
printf 'Port 2222\n' | sudo tee "$dropin" >/dev/null
echo 2222 >"$work/port"
run
refused "Port 2222" "other than 22"
sudo chmod 0600 "$dropin"
run
refused "unreadable Port 2222" "other than 22"
sudo rm -f "$dropin"
echo 22 >"$work/port"
: >"$work/sshd-fail"
run
refused "sshd -T failure" "sshd -T failed"
rm "$work/sshd-fail"

# as root, with a key: the root-login rule alone refuses it
rc=0
# shellcheck disable=SC2024 # sudo runs the hook only; the redirects are meant to write as this user
sudo env -u DJD_SKIP_SSH_CHECKS HOME="$work/home" bash "$hook" >"$work/out" 2>"$work/err" || rc=$?
refused "root" "normal user"

run
accepted "a key in authorized_keys"
rm "$work/home/.ssh/authorized_keys"
printf '%s\n' "$key" >"$work/home/.ssh/authorized_keys2"
run
accepted "a key in authorized_keys2"
mv "$work/home/.ssh/authorized_keys2" "$work/home/.ssh/authorized_keys"

printf 'Port 22\n' | sudo tee "$dropin" >/dev/null
run
accepted "Port 22"

sudo rm -f "$dropin"
if sudo test -f "$sshd_config"; then
    sudo cp "$sshd_config" "$work/sshd_config.orig"
    config_saved=1
fi
printf 'Include /etc/ssh/sshd_config.d/*.conf\n' | sudo tee "$sshd_config" >/dev/null
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' | sudo tee "$managed_dropin" >/dev/null
sudo tee "$sshd_stub" >/dev/null <<'EOF'
#!/bin/sh
echo passwordauthentication yes
echo kbdinteractiveauthentication no
echo permitrootlogin no
EOF
sudo chmod +x "$sshd_stub"
stub_created=1
run_keys_only() {
    rc=0
    bash "$keys_only" >"$work/out" 2>"$work/err" || rc=$?
}
run_keys_only
want_rc "managed sshd drop-in" 0
printf 'PasswordAuthentication yes\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' | sudo tee "$managed_dropin" >/dev/null
run_keys_only
refused "corrupted sshd drop-in" "not keys-only"

echo "server-hooks: ok"
