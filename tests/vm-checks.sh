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

# the Japanese locale is what orb and ssh forward to such a machine; the djd router has to undo it
LC_ALL=ja_JP.UTF-8 djd doctor
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
# published ports bypass ufw: the default bridge and new networks (compose's) bind to 127.0.0.1
bind='{{index .Options "com.docker.network.bridge.host_binding_ipv4"}}'
sudo docker network create djd-check >/dev/null
got=$(sudo docker network inspect djd-check -f "$bind")
sudo docker network rm djd-check >/dev/null
[ "$got" = 127.0.0.1 ] || {
    echo "new docker networks bind published ports to '$got'" >&2
    exit 1
}
got=$(sudo docker network inspect bridge -f "$bind")
[ "$got" = 127.0.0.1 ] || {
    echo "the default bridge binds published ports to '$got'" >&2
    exit 1
}
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
bash ~/.dotfiles/tests/desktop-apps.sh
# plan covers packages, files, services and the firewall; dotfiles and tools are checked by doctor
plan=$(mise bootstrap plan --detailed-exitcode 2>&1) || {
    printf '%s\n' "$plan" >&2
    exit 1
}
ok converged

djd module remove desktop >/dev/null
test ! -e ~/.xsession
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
