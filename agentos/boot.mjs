// Export the agentOS-portable subset of these dotfiles, or boot a VM with it and assert it works.
//   node agentos/boot.mjs --export <path>   write the bundle JSON (no agentOS needed)
//   node agentos/boot.mjs --lock            re-pin the registry packages in agentos/software.lock.json
//   node agentos/boot.mjs                   boot a VM, run checks in its shell, exit 0/1
import { mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_DIR = join(dirname(fileURLToPath(import.meta.url)), "..");
const GUEST_HOME = "/home/agentos";

// guest path (under GUEST_HOME) -> repo file. tests/agentos-bundle.sh lists the same five files, so a new entry
// fails CI until it is reviewed there.
const FILES = {
  ".profile": "home/.profile",
  ".config/git/config": "home/.config/git/config",
  ".config/git/ignore": "home/.config/git/ignore",
  ".config/git/commit.template": "home/.config/git/commit.template",
  ".gitconfig": "agentos/gitconfig",
};

// agentOS registry package -> the command it must put on the guest's PATH. tests/agentos-bundle.sh looks each
// command up in the sandbox image: an agent must not find in a guest a command the Ubuntu toolset lacks.
// Same name, different program: the registry `jq` is jaq and `yq` is the registry's own build.
// vim is omitted: the pinned release's vim package installs no commands.
const SOFTWARE = {
  git: "git",
  curl: "curl",
  jq: "jq",
  ripgrep: "rg",
  fd: "fd",
  yq: "yq",
  tree: "tree",
  sqlite3: "sqlite3",
  unzip: "unzip",
  zip: "zip",
};

const fail = (lines) => {
  console.error(lines.map((l) => `agentos: ${l}`).join("\n"));
  process.exit(1);
};

// Compares realpaths: that catches a tracked symlink and one in a directory above, either of which would copy a
// file from outside the repo into every VM. Hard links are not checked: git cannot store them.
async function readRepoFile(source) {
  const file = join(REPO_DIR, source);
  const resolved = await realpath(file);
  if (resolved !== join(await realpath(REPO_DIR), source)) fail([`${source}: resolves to ${resolved}; a symlink would leak its target`]);
  return readFile(file, "utf8");
}

// The registry packages are pinned in LOCK_FILE: the release (that of the agentos-core that package.json pins) and,
// per package, the URL and digest its manifest listed when `--lock` last ran. The manifest comes from the same
// server as the packages, so its digest alone detects a corrupt download but not a republished release.
const LOCK_FILE = "agentos/software.lock.json";
const RELOCK = "after reviewing what changed, run `mise run agentos:lock`";
const CORE = JSON.parse(await readFile(join(REPO_DIR, "agentos/package.json"), "utf8")).dependencies["@rivet-dev/agentos-core"];

// Offline: the lock names exactly the SOFTWARE packages, in the release this agentos-core resolves against.
async function readLock() {
  let lock;
  try {
    lock = JSON.parse(await readFile(join(REPO_DIR, LOCK_FILE), "utf8"));
  } catch (e) {
    fail([`${LOCK_FILE}: ${e.message}`, RELOCK]);
  }
  const packages = lock?.packages ?? {};
  const problems = [];
  if (lock?.core !== CORE) problems.push(`core is ${lock?.core}, but agentos/package.json pins @rivet-dev/agentos-core ${CORE}`);
  for (const name of Object.keys(SOFTWARE)) {
    const p = packages[name];
    if (!p) problems.push(`${name}: SOFTWARE names it, the lock does not`);
    else if (!/^sha256:[0-9a-f]{64}$/.test(p.digest) || !/^https:\/\//.test(p.url)) problems.push(`${name}: digest or url is malformed`);
  }
  for (const name of Object.keys(packages)) {
    if (!Object.hasOwn(SOFTWARE, name)) problems.push(`${name}: the lock has it, SOFTWARE does not`);
  }
  if (problems.length > 0) fail([`${LOCK_FILE} does not match boot.mjs and package.json`, ...problems, RELOCK]);
  return lock;
}

const files = await Promise.all(
  Object.entries(FILES).map(async ([rel, source]) => ({ path: `${GUEST_HOME}/${rel}`, content: await readRepoFile(source) })),
);
const pinned = (lock) => Object.keys(SOFTWARE).map((name) => ({ url: lock.packages[name].url, digest: lock.packages[name].digest }));

const exportIndex = process.argv.indexOf("--export");
if (exportIndex !== -1) {
  const out = process.argv[exportIndex + 1];
  if (!out) throw new Error("usage: boot.mjs --export <path>");
  // Checks the lock against SOFTWARE and package.json only: export has no network and no node_modules.
  const lock = await readLock();
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, `${JSON.stringify({ files, software: pinned(lock) }, null, 2)}\n`);
  console.log(`agentos: wrote ${out} (${files.length} files, ${Object.keys(SOFTWARE).length} packages)`);
  process.exit(0);
}

if (process.argv.includes("--lock")) {
  // The boot needs no such guard: it installs the locked `{ url, digest }` entries without a registry lookup.
  if (process.env.AGENTOS_SOFTWARE_REGISTRY_URL) {
    fail(["AGENTOS_SOFTWARE_REGISTRY_URL is set in the host environment; unset it to pin the default registry"]);
  }
  const { resolveRegistrySoftware } = await import("@rivet-dev/agentos-core");
  const names = Object.keys(SOFTWARE).sort();
  const resolved = await Promise.all(names.map((name) => resolveRegistrySoftware(name, { version: CORE })));
  const packages = Object.fromEntries(resolved.map(({ name, digest, url }) => [name, { digest, url }]));
  await writeFile(join(REPO_DIR, LOCK_FILE), `${JSON.stringify({ core: CORE, packages }, null, 2)}\n`);
  console.log(`agentos: wrote ${LOCK_FILE} (${names.length} packages, agentos-core ${CORE})`);
  process.exit(0);
}

const lock = await readLock();
const { AgentOs } = await import("@rivet-dev/agentos-core");

// The guest shell (brush) reads no startup files for exec/execFile: `-l` is ignored and BASH_ENV/ENV make it
// fail ("not yet implemented"). Checks source ~/.profile explicitly.
const PROFILE = '. "$HOME/.profile"';
// Each check runs in its own execFile. stdout is compared without its final newline. A check needs exit 0 and an
// empty stderr unless it says otherwise: `anyStderr` allows any stderr, `expectFailure` (a regex for stderr)
// needs a non-zero exit instead.
const CHECKS = [
  { name: "profile sources with exit 0 and no stderr", script: PROFILE, stdout: "" },
  {
    name: "profile exports",
    script: `${PROFILE} && printf '%s\\n' "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$DJD_DIR" "$LANG" "$TZ"`,
    stdout: [
      `${GUEST_HOME}/.config`,
      `${GUEST_HOME}/.local/share`,
      `${GUEST_HOME}/.local/state`,
      `${GUEST_HOME}/.cache`,
      `${GUEST_HOME}/.dotfiles`,
      "C.UTF-8",
      "Asia/Tokyo",
    ].join("\n"),
  },
  {
    // the no-file branch is the first check; this one proves the profile sources a file that exists
    name: "profile sources profile.local",
    script: `d=/tmp/djd-profile-$$ && mkdir -p "$d/djd" && printf 'export DJD_LOCAL=yes\\n' > "$d/djd/profile.local" && export XDG_CONFIG_HOME="$d" && ${PROFILE} && echo "$DJD_LOCAL"`,
    stdout: "yes",
  },
  {
    // brush already misreports `[ -r ]`, so show that `command -v` can say no before trusting the loop below
    name: "command -v fails for an unknown command",
    script: "command -v djd-no-such-command >/dev/null && echo found || echo absent",
    stdout: "absent",
  },
  {
    name: "every registry package is on PATH",
    script: `for c in ${Object.values(SOFTWARE).join(" ")}; do command -v "$c" >/dev/null || echo "missing:$c"; done`,
    stdout: "",
  },
  { name: "yq parses", script: "echo 'a: 1' | yq '.a'", stdout: "1" },
  { name: "shared git config is read", script: "git config --get init.defaultBranch", stdout: "main" },
  { name: "git pager neutralized", script: "git config --get core.pager", stdout: "cat" },
  { name: "git diffFilter neutralized", script: "git config --get interactive.diffFilter", stdout: "" },
  {
    name: "git credential helpers reset",
    script:
      'for h in github.com gist.github.com; do echo "[$(git config --get-all credential.https://$h.helper | tail -n 1)]"; done',
    stdout: "[]\n[]",
  },
  {
    name: "git init, commit and log work",
    script:
      'd=/tmp/djd-git-$$ && mkdir "$d" && cd "$d" && git init -q && git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init && git log --oneline',
    stdout: /^[0-9a-f]{7,} init$/,
    // git commit prints "fork failed" on stderr in the guest and still succeeds
    anyStderr: true,
  },
  {
    // Resolving is the only observable difference: under the default policy curl resolves the name and then fails
    // with exit 7 (getsockname), so any non-zero exit would also pass without `permissions`.
    name: "guest network is denied",
    script: "curl -sS --max-time 15 https://api.anthropic.com",
    stdout: "",
    expectFailure: /curl: \(6\) Could not resolve host: api\.anthropic\.com/,
  },
];

const sidecar = await AgentOs.createSidecar();
let vm;
const failures = [];
let timedOut = false;
try {
  vm = await AgentOs.create({
    sidecar: { kind: "explicit", handle: sidecar },
    // `{ url, digest }` entries skip the registry lookup: the sidecar downloads these URLs and rejects other bytes.
    software: pinned(lock),
    // The default policy lets the guest resolve api.anthropic.com (see the "guest network is denied" check).
    // Registry packages are downloaded by this host process, which network permissions do not cover, so denying
    // costs nothing.
    permissions: { network: "deny" },
    // the 30s default fails registry downloads on slow links
    packageResolver: { downloadTimeoutMs: 300_000 },
  });
  for (const dir of new Set(files.map((f) => dirname(f.path)))) {
    await vm.filesystem.mkdir(dir, { recursive: true });
  }
  for (const r of await vm.filesystem.writeFiles(files)) {
    if (!r.success) throw new Error(`write ${r.path}: ${r.error}`);
  }
  for (const check of CHECKS) {
    const r = await vm.process.execFile("sh", ["-c", check.script], { output: { capture: "all" }, timeoutMs: 60_000 });
    const stdout = (r.stdout ?? "").replace(/\n$/, "");
    const stderr = r.stderr ?? "";
    const stdoutOk = check.stdout instanceof RegExp ? check.stdout.test(stdout) : stdout === check.stdout;
    const statusOk = check.expectFailure
      ? r.outcome === "failed" && r.exitCode !== 0 && check.expectFailure.test(stderr)
      : r.outcome === "succeeded" && r.exitCode === 0 && (check.anyStderr || stderr === "");
    if (!statusOk || !stdoutOk) {
      failures.push(
        `${check.name}: outcome=${r.outcome} exit=${r.exitCode}\n  want stdout: ${check.stdout}${check.expectFailure ? `\n  want exit != 0 and stderr: ${check.expectFailure}` : ""}\n  stdout: ${JSON.stringify(stdout)}\n  stderr: ${JSON.stringify(stderr)}`,
      );
    }
  }
} catch (e) {
  // the sidecar's own acquisition wait (60s) is not configurable from here; the documented fix is to run again
  if (e.errno !== "ETIMEDOUT") throw e;
  timedOut = true;
} finally {
  await vm?.dispose();
  await sidecar.dispose();
}

if (timedOut) fail(["registry download timed out (slow link); run `mise run agentos:boot` again"]);
if (failures.length > 0) fail(["check failed", ...failures]);
console.log(`agentos: ok (${files.length} files, ${Object.keys(SOFTWARE).length} packages, ${CHECKS.length} checks)`);
process.exit(0);
