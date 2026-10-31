# AGENTS.md

Ubuntu 26.04-only dotfiles managed by mise. Read [docs/architecture.md](docs/architecture.md) and [docs/reference.md](docs/reference.md) before structural changes, and [docs/ci.md](docs/ci.md) before changing workflows or tests.

## Rules

- Scope is Ubuntu 26.04 (amd64, arm64). No macOS, WSL or other distros.
- Never run `install.sh`, `djd`, `mise bootstrap`, `mise dot` or `mise trust` on a machine you can't throw away. Test in Docker or a VM with the commands below.
- No secrets in the repo. Follow [SECURITY.md](SECURITY.md); per-machine values go in the local override files it lists.
- Run `mise run lint` before committing; CI runs the same task.

## Where things live

| To change | Edit |
| --- | --- |
| apt packages, tools, files every machine needs | `mise-config/config.toml` |
| agent runtimes and CLIs | `mise-config/config.agent.toml` |
| ssh, firewall, docker | `mise-config/config.server.toml` |
| XFCE, xrdp, Japanese input, ghostty | `mise-config/config.desktop.toml`, `desktop/` |
| the opt-in toolbox | `mise-config/config.full.toml` |
| encrypted env secrets | `mise-config/config.secrets.toml`, only through `djd secret set` (never plaintext) |
| dotfiles in `~` | `home/` (literal names, e.g. `home/.config/git/config`) |
| djd commands | `mise-config/tasks/djd/<name>` (bash, `#MISE description=`, `#MISE quiet=true`) |
| agentOS export | `agentos/boot.mjs` |
| repo tasks (lint, build, test, test:desktop, test:vm, ci) | `mise-tasks/<name>` (bash, `#MISE`/`#USAGE` headers; `lint` is the directory `mise-tasks/lint/` of `lint:*` checks), short ones in `mise.toml`. The `Makefile` runs `make <task>` as `mise run <task>`, except `init` (runs `install.sh`) and apply, update, status, doctor, module and secret (run `djd`) |
| repo tool versions | each task's `tools` (in `mise.toml`, or a `#MISE tools=` header in `mise-tasks/`), pinned in `mise.lock` plus `.mise/locks/` for npm tools (`mise lock --bump` advances them, and `lockfile_platforms` in `mise.toml` names the platforms; commit both) |
| colors, fonts, theme names | `DESIGN.md` first, then the files its Colors table names |

- Add a new tool to the lowest module that needs it, as `"latest"`.
- Everything outside `desktop` must work headless. A GUI package in another module gets `env = "desktop"`.
- `home/.profile` is shared by bash, zsh and agentOS: keep it POSIX, exports only.
- A new eval'd tool init in `.zshrc`/`.bashrc` goes through `_djd_init` (cached), not a bare `eval "$(tool init)"`, unless its output embeds per-shell state such as `PATH` (`mise activate`). `eval "$(sheldon source)"` also stays uncached, because its output follows `plugins.toml` edits.

## Verify

CI runs the same mise tasks (`lint`, `test`, `test:desktop`, `test:vm`, `agentos:boot`). On a machine where the repo is trusted by mise, run them directly (`make lint test`), or run a whole CI job with act (`mise run ci sandbox`). Everything runs in Docker or a throwaway incus or multipass VM, never on the host itself.

Without trusting the repo on the host, the task files run directly, and lint and agentOS run inside the sandbox image. `tests/tree.sh` streams only tracked and unignored files as a tar archive (nothing is mounted), so ignored files such as `age.txt` stay on the host:

```sh
export GITHUB_TOKEN="$(gh auth token)"   # any token works, and one without scopes is enough: see SECURITY.md#github-tokens
mise-tasks/build sandbox && mise-tasks/test/_default
mise-tasks/build desktop && mise-tasks/test/desktop
mise-tasks/test/vm   # incus, multipass or OrbStack
tests/tree.sh | docker run --rm -i -e GITHUB_TOKEN djd:sandbox zsh -lc 'mkdir /tmp/w && tar -xf - -C /tmp/w && cd /tmp/w && mise trust mise.toml && mise run lint && mise run agentos:boot'
```
