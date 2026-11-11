#!/usr/bin/env bash
# The real desktop-final hook against the image's xrdp configuration. Package removal and service activation are not
# under test; dpkg is stubbed off and the container has no running systemd. The container itself is disposable.
#
# Contract
#   - security_layer=tls is enforced in [Globals], not satisfied by a matching line in another section.
#   - AllowRootLogin=false is enforced in [Security], not satisfied by a matching line in another section.
#   - Doctor rejects both decoys before the repair and accepts the repaired files afterwards.
set -euo pipefail

cd "$(dirname "$0")/.."
[ ! -e .git ] || {
    echo "desktop-config: run through test:offline, not in a real checkout" >&2
    exit 2
}
repo=$(pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf '#!/bin/sh\nexit 1\n' >"$work/dpkg"
chmod +x "$work/dpkg"

sudo sed -i '0,/^security_layer=/s//security_layer=negotiate/' /etc/xrdp/xrdp.ini
sudo sed -i '0,/^AllowRootLogin=/s//AllowRootLogin=true/' /etc/xrdp/sesman.ini
printf '\n[decoy]\nsecurity_layer=tls\n' | sudo tee -a /etc/xrdp/xrdp.ini >/dev/null
printf '\n[decoy]\nAllowRootLogin=false\n' | sudo tee -a /etc/xrdp/sesman.ini >/dev/null

rc=0
out=$(cd "$HOME" && bash "$repo/mise-config/tasks/djd/doctor" 2>&1) || rc=$?
[ "$rc" -ne 0 ] || {
    echo "desktop-config: doctor accepted the decoys" >&2
    exit 1
}
[[ "$out" == *"FAIL xrdp-tls"* && "$out" == *"FAIL xrdp-root-login"* ]] || {
    echo "desktop-config: doctor missed an insecure section: $out" >&2
    exit 1
}

PATH="$work:$PATH" bash mise-config/hooks/desktop-final

ini_value() {
    awk -v section="[$2]" -v key="$3" '
        $0 == section { inside = 1; next }
        /^\[/ { inside = 0 }
        inside && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
    ' "$1"
}
[ "$(ini_value /etc/xrdp/xrdp.ini Globals security_layer)" = tls ] || {
    echo "desktop-config: [Globals] security_layer is not tls" >&2
    exit 1
}
[ "$(ini_value /etc/xrdp/sesman.ini Security AllowRootLogin)" = false ] || {
    echo "desktop-config: [Security] AllowRootLogin is not false" >&2
    exit 1
}
out=$(cd "$HOME" && bash "$repo/mise-config/tasks/djd/doctor" 2>&1) || {
    echo "desktop-config: doctor rejected the repaired files: $out" >&2
    exit 1
}
[[ "$out" == *"ok xrdp-tls"* && "$out" == *"ok xrdp-root-login"* ]] || {
    echo "desktop-config: doctor omitted a repaired check: $out" >&2
    exit 1
}
echo "desktop-config: ok"
