// Export the agentOS-portable subset of these dotfiles, or boot a VM with it and assert it works.
//   node agentos/boot.mjs --export <path>   write the bundle JSON (no agentOS needed)
//   node agentos/boot.mjs                   boot a VM, run checks in its shell, exit 0/1
import { constants } from "node:fs";
import { lstat, mkdir, open, readFile, realpath, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_DIR = join(dirname(fileURLToPath(import.meta.url)), "..");
const GUEST_HOME = "/home/agentos";

// guest path (under GUEST_HOME) -> repo file. ALLOWED_GUEST_PATHS is the same set written out a second time,
// so adding a FILES entry without updating it fails instead of leaking a file into every VM.
const FILES = {
  ".profile": "home/.profile",
  ".config/git/config": "home/.config/git/config",
  ".config/git/ignore": "home/.config/git/ignore",
  ".config/git/commit.template": "home/.config/git/commit.template",
  ".gitconfig": "agentos/gitconfig",
};
const ALLOWED_GUEST_PATHS = [
  `${GUEST_HOME}/.config/git/commit.template`,
  `${GUEST_HOME}/.config/git/config`,
  `${GUEST_HOME}/.config/git/ignore`,
  `${GUEST_HOME}/.gitconfig`,
  `${GUEST_HOME}/.profile`,
];

// agentOS registry package -> its declaration on the Ubuntu side: a [tools] key, or an apt: key under
// [bootstrap.packages], in mise-config/config.toml or config.agent.toml. Rule: the Ubuntu agent toolset is a
// superset of the agentOS one, so a command an agent finds in a guest also exists in the sandbox image.
// Same name, different program: the registry `jq` is jaq and `yq` is the registry's own build.
// vim is omitted: its 0.4.6 registry package installs no commands.
const SOFTWARE = {
  git: "apt:git",
  curl: "apt:curl",
  jq: "jq",
  ripgrep: "ripgrep",
  fd: "fd",
  yq: "yq",
  tree: "apt:tree",
  sqlite3: "apt:sqlite3",
  unzip: "apt:unzip",
  zip: "apt:zip",
};
// The guest's base env: `environment` replaces it, so this starts from agentos-core 0.4.6 base-filesystem.js.
// PAGER differs from that file (less): the guest has no less, and neither does it have vim for the EDITOR that
// home/.profile sets. vim installs no commands, and Ubuntu machines keep EDITOR=vim.
const BASE_ENV = {
  CHARSET: "UTF-8",
  HOME: GUEST_HOME,
  HOSTNAME: "agentos",
  LANG: "C.UTF-8",
  LC_COLLATE: "C",
  LOGNAME: "agentos",
  PAGER: "cat",
  PATH: "/usr/local/sbin:/usr/local/bin:/opt/agentos/bin:/usr/sbin:/usr/bin:/sbin:/bin",
  MANPATH: "/opt/agentos/share/man:/usr/local/share/man:/usr/share/man",
  SHELL: "/bin/sh",
  USER: "agentos",
  PS1: "\\h:\\w\\$ ",
};

const fail = (lines) => {
  console.error(lines.map((l) => `agentos: ${l}`).join("\n"));
  process.exit(1);
};

// A tracked symlink (the file, or a directory above it) or a hard link would copy a file from outside the repo
// into every VM. The checks are not atomic: someone who can rewrite the checkout while this runs can also
// edit the allowed files directly, so the opened handle is only compared with the lstat result to catch a swap.
async function readRepoFile(source) {
  const file = join(REPO_DIR, source);
  const linked = await lstat(file);
  if (!linked.isFile()) fail([`${source}: not a regular file (symlinks would leak their target)`]);
  if (linked.nlink !== 1) fail([`${source}: ${linked.nlink} hard links (a link could point outside the repo)`]);
  const [resolved, repo] = await Promise.all([realpath(file), realpath(REPO_DIR)]);
  if (resolved !== join(repo, source)) fail([`${source}: resolves to ${resolved}; a symlinked directory would leak its target`]);
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const opened = await handle.stat();
    if (opened.dev !== linked.dev || opened.ino !== linked.ino) fail([`${source}: changed while being read`]);
    return await handle.readFile("utf8");
  } finally {
    await handle.close();
  }
}

async function readBundleFiles() {
  const files = await Promise.all(
    Object.entries(FILES).map(async ([rel, source]) => {
      const path = `${GUEST_HOME}/${rel}`;
      if (rel.includes("..") || !path.startsWith(`${GUEST_HOME}/`)) fail([`${path}: outside ${GUEST_HOME}`]);
      return { path, content: await readRepoFile(source) };
    }),
  );
  const got = files.map((f) => f.path).sort();
  if (JSON.stringify(got) !== JSON.stringify(ALLOWED_GUEST_PATHS)) {
    fail(["bundle file set differs from ALLOWED_GUEST_PATHS", `got:     ${got.join(" ")}`, `allowed: ${ALLOWED_GUEST_PATHS.join(" ")}`]);
  }
  return files;
}

async function checkParity() {
  const toml = (
    await Promise.all(["config.toml", "config.agent.toml"].map((f) => readFile(join(REPO_DIR, "mise-config", f), "utf8")))
  ).join("\n");
  const undeclared = Object.entries(SOFTWARE).filter(([, key]) => {
    const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return !new RegExp(`^"?${escaped}"?\\s*=`, "m").test(toml);
  });
  if (undeclared.length > 0) {
    fail(undeclared.map(([name, key]) => `${name}: ${key} is not declared in mise-config/config.toml or config.agent.toml`));
  }
}

await checkParity();
const files = await readBundleFiles();

const exportIndex = process.argv.indexOf("--export");
if (exportIndex !== -1) {
  const out = process.argv[exportIndex + 1];
  if (!out) throw new Error("usage: boot.mjs --export <path>");
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, `${JSON.stringify({ files, software: Object.keys(SOFTWARE), environment: BASE_ENV }, null, 2)}\n`);
  console.log(`agentos: wrote ${out} (${files.length} files, ${Object.keys(SOFTWARE).length} packages)`);
  process.exit(0);
}

// The host fetches the package manifest from this registry, so a stray value would swap the guest's binaries.
if (process.env.AGENTOS_SOFTWARE_REGISTRY_URL) {
  fail(["AGENTOS_SOFTWARE_REGISTRY_URL is set in the host environment; unset it to boot from the default registry"]);
}

// The guest shell (brush) reads no startup files for exec/execFile: `-l` is ignored and BASH_ENV/ENV make it
// fail ("not yet implemented"). Checks source ~/.profile explicitly.
const PROFILE = '. "$HOME/.profile"';
// Each check runs in its own execFile. stdout is compared without its final newline; stderr must be empty
// unless the check says otherwise.
const CHECKS = [
  { name: "profile sources with exit 0 and no stderr", script: PROFILE, stdout: "" },
  {
    name: "profile exports and base env",
    script: `${PROFILE} && printf '%s\\n' "$XDG_CONFIG_HOME" "$DJD_DIR" "$PAGER"`,
    stdout: `${GUEST_HOME}/.config\n${GUEST_HOME}/.dotfiles\ncat`,
  },
  {
    name: "every registry package is on PATH",
    script: `for c in git curl jq rg fd yq tree sqlite3 unzip zip; do command -v "$c" >/dev/null || echo "missing:$c"; done`,
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
];

const { AgentOs } = await import("@rivet-dev/agentos-core");
const sidecar = await AgentOs.createSidecar();
let vm;
const failures = [];
try {
  vm = await AgentOs.create({
    sidecar: { kind: "explicit", handle: sidecar },
    software: Object.keys(SOFTWARE).map((registry) => ({ registry })),
    environment: BASE_ENV,
    // The default policy lets the guest reach api.anthropic.com. Registry packages are downloaded by this host
    // process, which network permissions do not cover, so denying costs nothing.
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
    if (r.outcome !== "succeeded" || r.exitCode !== 0 || !stdoutOk || (!check.anyStderr && stderr !== "")) {
      failures.push(
        `${check.name}: outcome=${r.outcome} exit=${r.exitCode}\n  want stdout: ${check.stdout}\n  stdout: ${JSON.stringify(stdout)}\n  stderr: ${JSON.stringify(stderr)}`,
      );
    }
  }
} finally {
  await vm?.dispose();
  await sidecar.dispose();
}

if (failures.length > 0) fail(["check failed", ...failures]);
console.log(`agentos: ok (${files.length} files, ${Object.keys(SOFTWARE).length} packages, ${CHECKS.length} checks)`);
process.exit(0);
