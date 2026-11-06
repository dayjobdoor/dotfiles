#!/usr/bin/env bash
# The agentOS export against a throwaway copy of the files boot.mjs reads: the bundle it writes, and each way it
# must refuse to write one. Offline: --export needs neither the network nor node_modules.
# Needs bash, coreutils and node, and the Ubuntu toolset on PATH (the sandbox image has it). usage: tests/agentos-bundle.sh
#
# Contract
#   - The bundle holds exactly the five allowlisted files under /home/agentos, with the repo's content, and the
#     locked { url, digest } of each of the ten registry packages, so it is pinned by itself.
#   - Each command a registry package must put on the guest's PATH exists in the environment this runs in.
#   - Nothing is written, and the exit status is non-zero with the cause named, when an allowed file is a symlink or
#     resolves outside the repo through a linked directory, or when the lock's core differs from package.json.
#     A set AGENTOS_SOFTWARE_REGISTRY_URL stops --lock before it reads any registry.
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
    rm -rf "$repo" "$work/out" "$work/outside"
    mkdir -p "$repo"
    cp -R "$root/agentos" "$root/home" "$repo/"
    rm -rf "$repo/agentos/node_modules"
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
if (keys !== "files software") bad(`bundle keys are: ${keys}`);
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
const entry = (p) => JSON.stringify({ url: p.url, digest: p.digest });
const locked = Object.values(JSON.parse(readFileSync(`${repo}/agentos/software.lock.json`, "utf8")).packages).map(entry).sort();
if (JSON.stringify(b.software.map(entry).sort()) !== JSON.stringify(locked)) bad(`software ${JSON.stringify(b.software)} differs from the lock`);
if (b.software.some((p) => Object.keys(p).length !== 2)) bad("a software entry has more than url and digest");
' "$out" "$repo" || fail "the baseline bundle is wrong"
echo "ok baseline bundle"

# The VM check looks up the same commands in the guest; here they must exist in the Ubuntu toolset. Read from the
# source because the list is the only thing that says which command each package provides.
# shellcheck disable=SC2016
cmds=$(node -e '
const m = require("node:fs").readFileSync(process.argv[1], "utf8").match(/^const SOFTWARE = (\{[^}]*\});/m);
if (!m) { console.error("agentos-bundle: no SOFTWARE in boot.mjs"); process.exit(1); }
const cmds = Object.values(new Function(`return ${m[1]}`)());
if (cmds.length !== 10) { console.error(`agentos-bundle: ${cmds.length} locked packages, want 10`); process.exit(1); }
console.log(cmds.join("\n"));
' "$repo/agentos/boot.mjs") || fail "cannot read the ten commands from SOFTWARE"
for c in $cmds; do
    command -v "$c" >/dev/null || fail "$c: a registry package provides it, but the Ubuntu toolset here does not"
done
echo "ok every registry command exists here"

fresh_copy
rm "$repo/home/.profile"
ln -s /etc/hostname "$repo/home/.profile"
expect_rejected "symlinked allowed file" "home/.profile" "resolves to"

fresh_copy
mv "$repo/home/.config/git" "$work/outside"
ln -s "$work/outside" "$repo/home/.config/git"
expect_rejected "file resolved outside the repo through a linked directory" "home/.config/git/" "resolves to"

fresh_copy
sed -i.bak 's|"@rivet-dev/agentos-core": "[^"]*"|"@rivet-dev/agentos-core": "0.0.1"|' "$repo/agentos/package.json"
rm "$repo/agentos/package.json.bak"
expect_rejected "lock core differs from package.json" "core is" "0.0.1"

# the lock names exactly the SOFTWARE packages, each with a sha256 digest and an https URL. mutate_lock CODE runs
# node over the copy's lock with `l` as the parsed file.
mutate_lock() {
    node -e '
const fs = require("node:fs");
const file = process.argv[1];
const l = JSON.parse(fs.readFileSync(file, "utf8"));
eval(process.argv[2]);
fs.writeFileSync(file, JSON.stringify(l, null, 2) + "\n");
' "$repo/agentos/software.lock.json" "$1"
}

fresh_copy
mutate_lock 'delete l.packages[Object.keys(l.packages)[0]]'
expect_rejected "lock lacks a package" "SOFTWARE names it"

fresh_copy
mutate_lock 'l.packages.bogus = { digest: "sha256:" + "0".repeat(64), url: "https://example.com/x" }'
expect_rejected "lock has an extra package" "SOFTWARE does not"

fresh_copy
mutate_lock 'const p = l.packages[Object.keys(l.packages)[0]]; p.digest = "sha256:abc"'
expect_rejected "lock digest malformed" "malformed"

fresh_copy
mutate_lock 'const p = l.packages[Object.keys(l.packages)[0]]; p.url = "http://example.com/x"'
expect_rejected "lock url not https" "malformed"

# an option is no output path: `--export --lock` must not write a file named --lock
fresh_copy
status=0
log=$(cd "$repo" && node agentos/boot.mjs --export --lock 2>&1) || status=$?
[ "$status" -ne 0 ] || fail "--export --lock was accepted"
[ ! -e "$repo/--lock" ] || fail "--export --lock wrote a file named --lock"
echo "ok --export refuses an option as its path"

# no node_modules in the copy: without the guard, --lock would stop at the import instead of naming the variable
fresh_copy
status=0
log=$(cd "$repo" && AGENTOS_SOFTWARE_REGISTRY_URL=http://127.0.0.1:1 node agentos/boot.mjs --lock 2>&1) || status=$?
[ "$status" -ne 0 ] || fail "--lock ran with AGENTOS_SOFTWARE_REGISTRY_URL set"
grep -qF AGENTOS_SOFTWARE_REGISTRY_URL <<<"$log" || fail "message does not name AGENTOS_SOFTWARE_REGISTRY_URL: $log"
cmp -s "$repo/agentos/software.lock.json" "$root/agentos/software.lock.json" || fail "--lock rewrote the lock with AGENTOS_SOFTWARE_REGISTRY_URL set"
echo "ok AGENTOS_SOFTWARE_REGISTRY_URL refused by --lock"
