// Export the agentOS-portable subset of these dotfiles, or boot a VM with it and assert it works.
//   node agentos/boot.mjs --export <path>   write the bundle JSON (no agentOS needed)
//   node agentos/boot.mjs                   boot a VM, run checks in its shell, exit 0/1
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HOME_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "home");
const GUEST_HOME = "/home/agentos";
const FILES = [".profile", ".config/git/config", ".config/git/ignore", ".config/git/commit.template"];
// vim is omitted: its 0.4.6 registry package installs no commands
const SOFTWARE = ["git", "curl", "jq", "ripgrep", "fd", "yq", "tree", "sqlite3", "unzip", "zip"];
// `environment` replaces the guest's base env, so start from agentos-core 0.4.6 base-filesystem.js verbatim.
const BASE_ENV = {
  CHARSET: "UTF-8",
  HOME: GUEST_HOME,
  HOSTNAME: "agentos",
  LANG: "C.UTF-8",
  LC_COLLATE: "C",
  LOGNAME: "agentos",
  PAGER: "less",
  PATH: "/usr/local/sbin:/usr/local/bin:/opt/agentos/bin:/usr/sbin:/usr/bin:/sbin:/bin",
  MANPATH: "/opt/agentos/share/man:/usr/local/share/man:/usr/share/man",
  SHELL: "/bin/sh",
  USER: "agentos",
  PS1: "\\h:\\w\\$ ",
};
// The guest shell (brush) reads no startup files for exec/execFile: `-l` is ignored and BASH_ENV/ENV
// make it fail ("not yet implemented"). Callers source ~/.profile explicitly.
const CHECK = [
  '. "$HOME/.profile"',
  'printf "%s\\n" "$XDG_CONFIG_HOME" "$DJD_DIR"',
  "git config --get init.defaultBranch",
  'for c in git jq rg fd yq tree curl sqlite3 unzip zip; do command -v "$c" >/dev/null || echo "missing:$c"; done',
].join("; ");
const EXPECTED = [`${GUEST_HOME}/.config`, `${GUEST_HOME}/.dotfiles`, "main"];

const files = await Promise.all(
  FILES.map(async (f) => ({ path: `${GUEST_HOME}/${f}`, content: await readFile(join(HOME_DIR, f), "utf8") })),
);

const exportIndex = process.argv.indexOf("--export");
if (exportIndex !== -1) {
  const out = process.argv[exportIndex + 1];
  if (!out) throw new Error("usage: boot.mjs --export <path>");
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, `${JSON.stringify({ files, software: SOFTWARE, environment: BASE_ENV }, null, 2)}\n`);
  console.log(`agentos: wrote ${out}`);
  process.exit(0);
}

const { AgentOs } = await import("@rivet-dev/agentos-core");
const sidecar = await AgentOs.createSidecar();
let vm;
let result;
try {
  vm = await AgentOs.create({
    sidecar: { kind: "explicit", handle: sidecar },
    software: SOFTWARE.map((registry) => ({ registry })),
    environment: BASE_ENV,
    // the 30s default fails registry downloads on slow links
    packageResolver: { downloadTimeoutMs: 300_000 },
  });
  for (const dir of new Set(files.map((f) => dirname(f.path)))) {
    await vm.filesystem.mkdir(dir, { recursive: true });
  }
  for (const r of await vm.filesystem.writeFiles(files)) {
    if (!r.success) throw new Error(`write ${r.path}: ${r.error}`);
  }
  result = await vm.process.execFile("sh", ["-c", CHECK], { output: { capture: "all" } });
} finally {
  await vm?.dispose();
  await sidecar.dispose();
}

const lines = (result.stdout ?? "").trim().split("\n");
const missing = lines.filter((l) => l.startsWith("missing:"));
const ok =
  result.outcome === "succeeded" && EXPECTED.every((want, i) => lines[i] === want) && missing.length === 0;
if (!ok) {
  console.error(`agentos: check failed (outcome=${result.outcome}, exit=${result.exitCode})`);
  console.error(`stdout:\n${result.stdout ?? ""}\nstderr:\n${result.stderr ?? ""}`);
  process.exit(1);
}
console.log(`agentos: ok (${files.length} files, ${SOFTWARE.length} packages)`);
process.exit(0);
