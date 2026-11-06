# AGENTS.md

Ubuntu 26.04-only dotfiles managed by mise. Read [docs/architecture.md](docs/architecture.md) and [docs/reference.md](docs/reference.md) before structural changes, and [docs/ci.md](docs/ci.md) before changing workflows or tests.

## Rules

- Scope is Ubuntu 26.04 (amd64, arm64). No macOS, WSL or other distros as targets; a Mac appears only as the host of Docker, act and the VM tools.
- Never run `install.sh`, `djd`, `mise bootstrap`, `mise dot`, `mise trust` or `mise run agentos:boot` on a machine you can't throw away. Test in Docker or a VM with the commands below.
- Use absolute paths inside this checkout. `djd`, `install.sh` and the djd tasks act on `~/.dotfiles`, never on the current directory.
- No secrets in the repo. Follow [SECURITY.md](SECURITY.md); per-machine values go in the local override files it lists.
- Test assertions: `! cmd` is exempt from `set -e`, and zsh has no `pipefail`, so `cmd | grep -q` hides the exit status of `cmd`. Write `if cmd; then exit 1; fi` and use here-strings. Make each new check fail once on a broken copy before you trust it.
- Done means `mise run lint` and the narrowest test below pass, and every hit of `git grep -n <changed name> -- '*.md' llms.txt` is updated. `lint:docs` checks links, anchors and the repo paths, commands and `DJD_` variables in code spans, but not prose, so prose can drift.

## Verify

CI runs the same mise tasks (`lint`, `test`, `test:desktop`, `test:vm`, `agentos:boot`). Tests that install or apply anything run in Docker or a throwaway incus, multipass or OrbStack VM, never on the host. `make lint` runs on the host and installs its user-level tools there. On a machine where the repo is trusted by mise, run the tasks directly (`make lint test`), run one lint check (`mise run lint:docs`, `lint:shell`, `lint:config`, `lint:workflows`, `lint:design`, `lint:secrets`), or run the offline tests alone on an existing `djd:sandbox` (`mise run test:offline djd-module`, about 1 s; no name runs all five, about 40 s). A whole CI job runs with act (`mise run ci sandbox`).

Without trusting the repo on the host, the task files run directly, and lint and agentOS run inside the sandbox image. `tests/tree.sh` streams only tracked and unignored files as a tar archive (nothing is mounted), so ignored files such as `age.txt` stay on the host:

```sh
export GITHUB_TOKEN=   # empty builds anonymously; or a token with no scopes (SECURITY.md#github-tokens). Never `gh auth token`
bash mise-tasks/lint/docs   # needs only bash; docs links, anchors, paths and commands
mise-tasks/test/offline     # the five offline tests on an existing djd:sandbox, about 40 s
mise-tasks/build sandbox && mise-tasks/test/_default
mise-tasks/build desktop && mise-tasks/test/desktop
mise-tasks/test/vm   # incus, multipass or OrbStack
tests/tree.sh | docker run --rm -i -e GITHUB_TOKEN djd:sandbox zsh -lc 'mkdir /tmp/w && tar -xf - -C /tmp/w && cd /tmp/w && mise trust mise.toml && mise run lint && mise run agentos:boot'
```

## Where things live

| To change | Edit |
| --- | --- |
| apt packages, tools, files every machine needs | `mise-config/config.toml` |
| agent runtimes and CLIs, their env, the global AGENTS.md of pi and omp | `mise-config/config.agent.toml`, `agent/` |
| ssh, firewall, docker | `mise-config/config.server.toml`, `mise-config/hooks/server-post-packages`, `server-pre-dotfiles` and `sshd-keys-only` |
| XFCE, xrdp, Japanese input, ghostty, brave, zen, zed, HackGen NF | `mise-config/config.desktop.toml`, `mise-config/hooks/desktop-final`, `desktop/` |
| the Docker images, the desktop entrypoint, compose | `.devcontainer/` (the desktop password and the TLS key are handled in `desktop-entrypoint.sh`) |
| the opt-in toolbox | `mise-config/config.full.toml` |
| encrypted env secrets | `mise-config/config.secrets.toml`, only through `djd secret set` (never plaintext) |
| dotfiles in `~` | `home/` (literal names, e.g. `home/.config/git/config`) |
| zsh plugins | `[bootstrap.repos]` in `mise-config/config.toml`, each pinned by `ref`; `home/.config/zsh/.zshrc` loads them |
| djd commands | `mise-config/tasks/djd/<name>` (bash, `#MISE description=`, `#MISE quiet=true`) |
| agentOS export | `agentos/boot.mjs`, `agentos/gitconfig`, `agentos/software.lock.json` (refresh with `mise run agentos:lock`); the command of every registry tool in `boot.mjs` must exist in the sandbox image, which `tests/agentos-bundle.sh` checks |
| repo tasks (lint, build, test, test:offline, test:desktop, test:vm, ci) | `mise-tasks/<name>` (bash, `#MISE`/`#USAGE` headers; `lint` is the directory `mise-tasks/lint/` of `lint:*` checks), short ones in `mise.toml`. The `Makefile` runs `make <task>` as `mise run <task>`, except `init` (runs `install.sh`) and apply, update, status, doctor, module and secret (run `djd`) |
| an offline test (no network, no token) | `tests/<name>.sh` with a `# Contract` header. Add its name to the `choices` and to the default list in `mise-tasks/test/offline`, which `mise run test` calls, and name it in `docs/reference.md`; `lint:docs` fails when the docs or the tasks miss it |
| a check that needs systemd, RDP or an image (the [test map](docs/ci.md#test-map) lists every test) | `tests/vm-checks.sh` (it refuses to run unless `test:vm` sets `DJD_TEST_VM=1`), `mise-tasks/test/desktop`, or a `doctor_says` scenario in `mise-tasks/test/_default` |
| docs | `docs/reference.md` for facts, `docs/architecture.md` for why, `docs/ci.md` for CI and tests, `docs/how-to.md` for procedures; `llms.txt` lists them |
| repo tool versions | each task's `tools` (in `mise.toml`, or a `#MISE tools=` header in `mise-tasks/`), pinned in `mise.lock` plus `.mise/locks/` for npm tools (`mise lock --bump` advances them, and `lockfile_platforms` in `mise.toml` names the platforms; commit both) |
| colors, fonts, theme names | `DESIGN.md` first, then the files its Colors table names |

- Add a new tool to the lowest module that needs it, as `"latest"`.
- Everything outside `desktop` must work headless. A GUI package in another module gets `env = "desktop"`.
- `home/.profile` is shared by bash, zsh and agentOS: keep it POSIX, exports only. Test files with `-f`, never `-r`, because the agentOS shell says `[ -r <missing file> ]` is true.
- A new eval'd tool init in `.zshrc`/`.bashrc` goes through `_djd_init` (cached), not a bare `eval "$(tool init)"`, unless its output embeds per-shell state such as `PATH` (`mise activate`, the one init that stays uncached).
- A new zsh plugin is a `[bootstrap.repos]` entry with a full commit `ref`, sourced from `.zshrc` through `zsh-defer`. Sheldon is gone.
