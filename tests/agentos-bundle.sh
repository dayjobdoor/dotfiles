#!/usr/bin/env bash
# The agentOS export against a throwaway copy of the files boot.mjs reads: the bundle it writes, and each way it
# must refuse to write one. Offline: --export needs neither the network nor node_modules.
# Needs bash, coreutils and node. usage: tests/agentos-bundle.sh
#
# Contract
#   - The bundle holds exactly the five allowlisted files under /home/agentos, with the repo's content, one
#     package per locked registry package, and the base environment.
#   - Nothing is written, and the exit status is non-zero with the cause named, when an allowed file is a symlink or
#     has a second hard link, when it resolves outside the repo through a linked directory, when FILES and
#     ALLOWED_GUEST_PATHS disagree, when a package has no declaration in the Ubuntu configs, or when the lock's
#     core differs from package.json. A set AGENTOS_SOFTWARE_REGISTRY_URL stops a boot.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# outside the checkout: the mise shim for node would otherwise read an untrusted mise.toml from here
cd "$work"
repo=$work/repo
out=$work/out/bundle.json

fail() {
    echo "agentos-bundle: $1" >&2
    exit 1
}

fresh_copy() {
    rm -rf "$repo" "$work/out" "$work/outside" "$work/hardlink"
    mkdir -p "$repo/mise-config"
    cp -R "$root/agentos" "$root/home" "$repo/"
    rm -rf "$repo/agentos/node_modules"
    cp "$root"/mise-config/config*.toml "$repo/mise-config/"
}

# runs the real export in the copy; sets status and log
run_export() {
    status=0
    log=$(cd "$repo" && node agentos/boot.mjs --export "$out" 2>&1) || status=$?
}

# expect_rejected NAME CAUSE...: the mutation already applied to the copy must stop the export, name every CAUSE word
# in its message, and leave no bundle behind
expect_rejected() {
    local name=$1 word
    shift
    run_export
    [ "$status" -ne 0 ] || fail "$name: export succeeded"
    for word in "$@"; do
        grep -qF -- "$word" <<<"$log" || fail "$name: message does not name '$word': $log"
    done
    [ ! -e "$out" ] || fail "$name: a bundle was written anyway"
    echo "ok $name"
}

fresh_copy
run_export
[ "$status" -eq 0 ] || fail "export of the unmodified copy failed ($status): $log"
# shellcheck disable=SC2016
node -e '
const { readFileSync } = require("node:fs");
const [bundle, repo] = process.argv.slice(1);
const b = JSON.parse(readFileSync(bundle, "utf8"));
const bad = (m) => { console.error(`agentos-bundle: ${m}`); process.exit(1); };
const keys = Object.keys(b).sort().join(" ");
if (keys !== "environment files software") bad(`bundle keys are: ${keys}`);
const want = {
  "/home/agentos/.profile": "home/.profile",
  "/home/agentos/.config/git/config": "home/.config/git/config",
  "/home/agentos/.config/git/ignore": "home/.config/git/ignore",
  "/home/agentos/.config/git/commit.template": "home/.config/git/commit.template",
  "/home/agentos/.gitconfig": "agentos/gitconfig",
};
if (b.files.length !== 5) bad(`${b.files.length} files, want 5`);
for (const [path, source] of Object.entries(want)) {
  const f = b.files.find((x) => x.path === path);
  if (!f) bad(`no ${path} in the bundle`);
  if (f.content !== readFileSync(`${repo}/${source}`, "utf8")) bad(`${path} differs from ${source}`);
}
const locked = Object.keys(JSON.parse(readFileSync(`${repo}/agentos/software.lock.json`, "utf8")).packages).sort();
if (JSON.stringify([...b.software].sort()) !== JSON.stringify(locked)) bad(`software ${b.software} differs from the lock ${locked}`);
if (b.environment.HOME !== "/home/agentos") bad(`environment HOME is ${b.environment.HOME}`);
' "$out" "$repo" || fail "the baseline bundle is wrong"
echo "ok baseline bundle"

fresh_copy
rm "$repo/home/.profile"
ln -s /etc/hostname "$repo/home/.profile"
expect_rejected "symlinked allowed file" "home/.profile" "not a regular file"

fresh_copy
ln "$repo/home/.profile" "$work/hardlink"
expect_rejected "hard-linked allowed file" "home/.profile" "hard links"

fresh_copy
mv "$repo/home/.config/git" "$work/outside"
ln -s "$work/outside" "$repo/home/.config/git"
expect_rejected "file resolved outside the repo through a linked directory" "home/.config/git/" "resolves to"

fresh_copy
sed -i.bak 's|^  ".profile": "home/.profile",|&\n  ".bashrc": "home/.bashrc",|' "$repo/agentos/boot.mjs"
rm "$repo/agentos/boot.mjs.bak"
grep -qF '".bashrc": "home/.bashrc"' "$repo/agentos/boot.mjs" || fail "setup: FILES entry was not added to the copy"
expect_rejected "FILES entry missing from ALLOWED_GUEST_PATHS" "ALLOWED_GUEST_PATHS" "/home/agentos/.bashrc"

fresh_copy
sed -i.bak '/^ripgrep = /d' "$repo/mise-config/config.toml"
rm "$repo/mise-config/config.toml.bak"
expect_rejected "package without a declaration" "ripgrep" "not declared"

fresh_copy
sed -i.bak 's|"@rivet-dev/agentos-core": "[^"]*"|"@rivet-dev/agentos-core": "0.0.1"|' "$repo/agentos/package.json"
rm "$repo/agentos/package.json.bak"
expect_rejected "lock core differs from package.json" "core is" "0.0.1"

# the registry override is checked on the boot and lock paths, before agentos-core is imported
fresh_copy
status=0
log=$(cd "$repo" && AGENTOS_SOFTWARE_REGISTRY_URL=http://127.0.0.1:1 node agentos/boot.mjs 2>&1) || status=$?
[ "$status" -ne 0 ] || fail "boot ran with AGENTOS_SOFTWARE_REGISTRY_URL set"
grep -qF AGENTOS_SOFTWARE_REGISTRY_URL <<<"$log" || fail "message does not name AGENTOS_SOFTWARE_REGISTRY_URL: $log"
echo "ok AGENTOS_SOFTWARE_REGISTRY_URL refused"
