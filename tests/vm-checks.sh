#!/usr/bin/env bash
# Runs inside the VM after the README's `curl | sh -s -- server desktop` install (see mise-tasks/test/vm).
set -euo pipefail
# set -e alone fails silently; name the check that stopped the run
trap 'echo "FAIL line $LINENO: $BASH_COMMAND" >&2' ERR
export PATH="$HOME/.local/bin:$PATH"
# mise parses English ufw output (see home/.local/bin/djd)
export LC_ALL=C.UTF-8

ok() { echo "ok $*"; }

for f in ~/.dotfiles/cloud-init/*.yaml; do
    sudo cloud-init schema -c "$f" >/dev/null
done
ok cloud-init schema

# install.sh cloned the repo (the curl | sh path) instead of linking a checkout
test ! -L ~/.dotfiles
git -C ~/.dotfiles rev-parse --verify -q HEAD >/dev/null
ok install.sh cloned the repo

# the Japanese locale is what orb and ssh forward to such a machine; the djd router has to undo it. Control: under
# this locale ufw does not speak English (mise matches "Status: active"), or the doctor run below would pass even
# without the router. env, because sudo may drop LC_ALL.
ja=$(sudo env LC_ALL=ja_JP.UTF-8 ufw status)
if grep -q '^Status: active' <<<"$ja"; then
    echo "ufw still prints English under ja_JP.UTF-8: the locale check proves nothing" >&2
    exit 1
fi
doctor=$(LC_ALL=ja_JP.UTF-8 djd doctor)
# server and desktop are selected: doctor checks what the hooks enforce, and a missing line would mean it skipped them
for check in ubuntu sshd xrdp-tls xrdp-root-login; do
    grep -qx "ok $check" <<<"$doctor" || {
        echo "doctor has no 'ok $check' line: $doctor" >&2
        exit 1
    }
done
ufw=$(sudo ufw status)
grep -qE '^22/tcp +LIMIT +Anywhere' <<<"$ufw"
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/7 fe80::/10; do
    grep -qE "^3389/tcp +ALLOW +${net//./\\.}( |$)" <<<"$ufw" || {
        echo "firewall: no RDP rule for $net" >&2
        exit 1
    }
done
# RDP only from private networks, and no unicast mDNS rule (ufw's before.rules handles multicast)
if grep -qE '^3389/tcp( \(v6\))? +ALLOW +Anywhere|^5353' <<<"$ufw"; then
    echo "firewall: RDP or mDNS open to everyone" >&2
    exit 1
fi
# `verbose` prints the default policy but also rewrites the rule lines, so it is a separate call
grep -q '^Default: deny (incoming)' <<<"$(sudo ufw status verbose)"
ok firewall
# A login attempt starts the socket-activated sshd, and the denial lists the methods it offers
denied=$(ssh -o BatchMode=yes -o PubkeyAuthentication=no -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null localhost true 2>&1 || true)
grep -q 'Permission denied (publickey)\.' <<<"$denied" || {
    echo "sshd offers more than public keys: $denied" >&2
    exit 1
}
# sshd -T needs /run/sshd, which the started ssh.service now provides. Cloud images already turn passwords
# off and Ubuntu's sshd_config already sets keyboard-interactive to no; only root login (prohibit-password
# by default) proves our drop-in is the one in effect.
sshd=$(sudo sshd -T)
grep -qx 'passwordauthentication no' <<<"$sshd"
grep -qx 'kbdinteractiveauthentication no' <<<"$sshd"
grep -qx 'permitrootlogin no' <<<"$sshd"
ok sshd keys only
# Published ports bypass ufw: the default bridge and new networks (compose's) bind them to 127.0.0.1. Checked
# by publishing one and reading the listening socket, not the network's option. The EXIT trap removes the
# container when an assertion fails.
trap 'sudo docker rm -f djd-check >/dev/null 2>&1 || true; sudo docker network rm djd-net >/dev/null 2>&1 || true' EXIT
sudo docker network create djd-net >/dev/null
for net in bridge djd-net; do
    sudo docker run -d --rm --name djd-check --network "$net" -p 80 busybox sleep 600 >/dev/null
    ports=$(sudo docker port djd-check 80/tcp)
    port=${ports%%$'\n'*}
    port=${port##*:}
    listeners=$(ss -ltn)
    grep -qE "[[:space:]]127\.0\.0\.1:${port}[[:space:]]" <<<"$listeners" || {
        echo "network $net: nothing listens on 127.0.0.1:$port: $listeners" >&2
        exit 1
    }
    if grep -qE "[[:space:]](0\.0\.0\.0|\*|\[::\]):${port}[[:space:]]" <<<"$listeners"; then
        echo "network $net publishes port $port on every interface: $listeners" >&2
        exit 1
    fi
    sudo docker rm -f djd-check >/dev/null
done
sudo docker network rm djd-net >/dev/null
trap - EXIT
ok docker publishes on 127.0.0.1
# sshd is socket-activated on 26.04: ssh.service stays idle until a connection
for unit in ssh.socket avahi-daemon xrdp docker; do
    systemctl is-active --quiet "$unit" || {
        echo "$unit is not active" >&2
        exit 1
    }
done
ok services
id -nG "$USER" | grep -qw docker
ok docker group
# pam_env reads /etc/default/locale, which 26.04 links to /etc/locale.conf
grep -qx 'LANG=ja_JP.UTF-8' /etc/default/locale
grep -qi '^ja_JP.utf8$' <<<"$(locale -a)"
# a here-string, not a pipe: grep -q exiting early would SIGPIPE fc-list under pipefail
grep -q 'HackGen35 Console NF' <<<"$(fc-list : family)"
ok desktop locale and font
grep -qx security_layer=tls /etc/xrdp/xrdp.ini
grep -qx AllowRootLogin=false /etc/xrdp/sesman.ini
bash ~/.dotfiles/tests/desktop-apps.sh
# plan covers packages, files, services and the firewall; doctor adds the Ubuntu release, the mise link, the login
# shell, the dotfiles, and the sshd and xrdp settings that the hooks enforce
plan=$(mise bootstrap plan --detailed-exitcode 2>&1) || {
    printf '%s\n' "$plan" >&2
    exit 1
}
ok converged

# sshd keeps the first value it reads, so a drop-in that sorts before ours can turn passwords back on. apply
# and doctor must both refuse that. The file goes before any assertion, so that a red run leaves the machine
# as it was; the VM is only kept with DJD_KEEP_VM. The running daemon is not asserted: the hook does not restart it.
guard=/etc/ssh/sshd_config.d/00-djd-test.conf
echo 'PasswordAuthentication yes' | sudo tee "$guard" >/dev/null
apply_rc=0
apply_out=$(djd apply 2>&1) || apply_rc=$?
doctor_rc=0
doctor_out=$(djd doctor 2>&1) || doctor_rc=$?
sudo rm -f "$guard"
if [ "$apply_rc" = 0 ]; then
    echo "djd apply accepted a drop-in that turns passwords on" >&2
    exit 1
fi
grep -q 'keys-only' <<<"$apply_out" || {
    echo "djd apply failed, but not on sshd: $apply_out" >&2
    exit 1
}
if [ "$doctor_rc" = 0 ]; then
    echo "djd doctor accepted a drop-in that turns passwords on" >&2
    exit 1
fi
grep -q '^FAIL sshd' <<<"$doctor_out" || {
    echo "djd doctor failed, but not on sshd: $doctor_out" >&2
    exit 1
}
# without the drop-in the same apply succeeds, so the refusal was the drop-in's doing
djd apply >/dev/null
djd doctor >/dev/null
ok sshd override refused by apply and doctor

# the module never adds --no-sandbox to Brave (only the Docker image does). Control: the file the grep would
# read is there, or the grep below would find nothing in a missing file.
test -f /usr/share/applications/brave-browser.desktop
if grep -rq -- --no-sandbox ~/.local/share/applications /usr/share/applications/brave-browser.desktop 2>/dev/null; then
    echo "Brave is launched with --no-sandbox" >&2
    exit 1
fi
ok brave keeps its sandbox

# the module removal deletes the apt source mise added for Brave, or the repository would stay trusted
test -e /etc/apt/sources.list.d/mise-brave-browser.sources
djd module remove desktop >/dev/null
test ! -e ~/.xsession
test ! -e /etc/apt/sources.list.d/mise-brave-browser.sources
grep -qx 'LANG=C.UTF-8' /etc/default/locale
djd doctor
ok module remove desktop

# unapply deletes the files a module wrote and leaves its packages and firewall rules, so SSH stays reachable
djd module remove server >/dev/null
test ! -e /etc/ssh/sshd_config.d/10-djd.conf
test ! -e /etc/docker/daemon.json
grep -qE '^22/tcp +LIMIT +Anywhere' <<<"$(sudo ufw status)"
djd doctor
ok module remove server
