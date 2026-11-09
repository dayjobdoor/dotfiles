#!/usr/bin/env bash
# The server module's post-packages hook: it refuses an apply that would lock the user out of ssh. Run it inside
# the image; it needs sudo (the image's dayjobdoor user has it without a password) and bash.
# usage: tests/server-hooks.sh
#
# Contract
#   - No key in ~/.ssh/authorized_keys (missing file, empty file, only comments) exits 1 and says it holds no key.
#   - A Port other than 22 in sshd_config.d exits 1 and says so.
#   - Running as root exits 1: the module turns root login off.
#   - None of those refusals adds the user to the docker group (the hook grants it only after its checks).
#   - A key line in authorized_keys or authorized_keys2, Port 22, and DJD_SKIP_SSH_CHECKS=1 without a key all exit 0,
#     and each leaves the user in the docker group.
#   - The caller's DJD_SKIP_SSH_CHECKS is dropped from every run but the one that sets it: left in, it would make
#     every "must refuse" case pass without the checks running.
#
# The hook is run for real. It changes the machine: the docker group (created if missing) and the sshd_config.d
# directory stay; the user's docker membership and a drop-in under /etc/ssh/sshd_config.d are removed again.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
hook=$here/../mise-config/hooks/server-post-packages
work=$(mktemp -d)
dropin=/etc/ssh/sshd_config.d/99-djd-test.conf
me=$(id -un)
cleanup() {
    sudo rm -f "$dropin"
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
run DJD_SKIP_SSH_CHECKS=1
accepted "check skipped"

key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK test@example'
printf '%s\n' "$key" >"$work/home/.ssh/authorized_keys"
printf 'Port 2222\n' | sudo tee "$dropin" >/dev/null
run
refused "Port 2222" "other than 22"
sudo rm -f "$dropin"

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

echo "server-hooks: ok"
