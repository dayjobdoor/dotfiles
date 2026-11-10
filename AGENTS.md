# AGENTS.md

Ubuntu 26.04-only dotfiles managed by mise. Read [docs/requirements.md](docs/requirements.md), [docs/architecture.md](docs/architecture.md) and [docs/directory.md](docs/directory.md) before structural changes, [docs/problems.md](docs/problems.md) before touching what it lists, [docs/maintenance.md](docs/maintenance.md) before changing workflows and [docs/testing.md](docs/testing.md) before changing tests.

## Rules

- Scope is Ubuntu 26.04 (amd64, arm64). No macOS, WSL or other distros as targets; a Mac appears only as the host of Docker, act and the VM tools.
- Never run `install.sh`, `djd`, `mise bootstrap`, `mise dot` or `mise trust` on a machine you can't throw away. Test in Docker or a VM with the commands below.
- Use absolute paths inside this checkout. `djd`, `install.sh` and the djd tasks act on `~/.dotfiles`, never on the current directory.
- No secrets in the repo. Follow [SECURITY.md](SECURITY.md); per-machine values go in the local override files it lists.
- Test assertions: `! cmd` is exempt from `set -e`, and zsh has no `pipefail`, so `cmd | grep -q` hides the exit status of `cmd`. Write `if cmd; then exit 1; fi` and use here-strings. Make each new check fail once on a broken copy before you trust it.
- Done means `mise run lint` and the narrowest test below pass, and every hit of `git grep -n <changed name> -- '*.md' llms.txt` is updated. `lint:docs` checks links, anchors and the repo paths, commands and `DJD_` variables in code spans, but not prose, so prose can drift.

## Verify

CI runs the same mise tasks (`lint`, `test`, `test:desktop`, `test:vm`). Tests that install or apply anything run in Docker or a throwaway incus or multipass VM, never on the host. `make lint` runs on the host and installs its user-level tools there. On a machine where the repo is trusted by mise, run the tasks directly (`make lint test`), run one lint check (`mise run lint:docs`, `lint:shell`, `lint:config`, `lint:workflows`, `lint:design`, `lint:secrets`), or run the offline tests alone on an existing `djd:latest` (`mise run test:offline djd-module`; no name runs all four, and `xsession-audio` is the slow one, see [docs/testing.md](docs/testing.md#test-map)). A whole CI job runs with act (`mise run ci image`).

Without trusting the repo on the host, the task files run directly, and lint runs inside the image. `tests/tree.sh` streams only tracked and unignored files as a tar archive (nothing is mounted), so ignored files such as `age.txt` stay on the host:

```sh
export GITHUB_TOKEN=   # empty builds anonymously; or a token with no scopes (SECURITY.md#github-tokens). Never `gh auth token`
bash .mise/tasks/lint/docs   # needs only bash; docs links, anchors, paths and commands
.mise/tasks/test/offline     # the four offline tests on an existing djd:latest
.mise/tasks/build && .mise/tasks/test/_default
.mise/tasks/test/desktop     # builds the same image first
.mise/tasks/test/vm   # incus or multipass
tests/tree.sh | docker run --rm -i -e GITHUB_TOKEN djd:latest zsh -lc 'mkdir /tmp/w && tar -xf - -C /tmp/w && cd /tmp/w && mise trust .mise/config.toml && mise run lint'
```

## Where things live

| To change | Edit |
| --- | --- |
| apt packages, tools, files every machine needs | `mise-config/config.toml` |
| agent runtimes and CLIs, their env | `mise-config/config.agent.toml` |
| pi and omp config: settings, instructions, extensions, skills | `home/.config/pi/`, `home/.config/omp/` |
| ssh, firewall, docker | `mise-config/config.server.toml`, `mise-config/hooks/server-post-packages`, `server-pre-dotfiles` and `sshd-keys-only` |
| XFCE, xrdp, Japanese input, ghostty, brave, zen, zed, HackGen NF, wireshark, obsidian, vicinae, ferdium, fusuma | `mise-config/config.toml` (the desktop is part of the base), `mise-config/hooks/desktop-final`, `home/` |
| the Docker image, the desktop entrypoint, compose | `.devcontainer/` (the desktop password and the TLS key are handled in `desktop-entrypoint.sh`) |
| the opt-in toolbox | `mise-config/config.full.toml` |
| encrypted env secrets | `mise-config/config.secrets.toml`, only through `djd secret set` (never plaintext) |
| dotfiles in `~` | `home/` (literal names, e.g. `home/.config/git/config`) |
| zsh plugins, abbreviations | `home/.config/sheldon/plugins.toml` (sheldon, each plugin pinned by `rev`), `home/.config/zsh-abbr/user-abbreviations`; `home/.config/zsh/.zshrc` loads them. Aliases that replace a command are `[shell_alias]` in `mise-config/config.toml` |
| djd commands | `mise-config/tasks/djd/<name>` (bash, `#MISE description=`, `#MISE quiet=true`) |
| repo tasks (lint, build, test, test:offline, test:desktop, test:vm, ci) | `.mise/tasks/<name>` (bash, `#MISE`/`#USAGE` headers; `lint` is the directory `.mise/tasks/lint/` of `lint:*` checks), short ones in `.mise/config.toml`. The `Makefile` runs `make <task>` as `mise run <task>`, except `init` (runs `install.sh`) and apply, update, status, doctor, module and secret (run `djd`) |
| an offline test (no network, no token) | `tests/<name>.sh` with a `# Contract` header. Add its name to the `choices` and to the default list in `.mise/tasks/test/offline`, which `mise run test` calls, and name it in the layout of `docs/directory.md`; `lint:docs` fails when the docs or the tasks miss it |
| a check that needs systemd, RDP or an image (the [test map](docs/testing.md#test-map) lists every test) | `tests/vm-checks.sh` (it refuses to run unless `test:vm` sets `DJD_TEST_VM=1`), `.mise/tasks/test/desktop`, or a `doctor_says` scenario in `.mise/tasks/test/_default` |
| docs | `docs/requirements.md` for what ships, `docs/architecture.md` for how and why, `docs/tech.md` for the stack and the lookup tables, `docs/directory.md` for where files live, `docs/problems.md` for pitfalls and limits, `docs/references.md` for terms and sources, `docs/maintenance.md` for workflows and releases, `docs/testing.md` for tests, `docs/guidance.md` for procedures; `ROADMAP.md` for what is planned and `CHANGELOG.md` for what shipped; `llms.txt` lists them |
| repo tool versions | each task's `tools` (in `.mise/config.toml`, or a `#MISE tools=` header in `.mise/tasks/`), pinned in `.mise/mise.lock` plus `.mise/locks/` for npm tools (`mise lock --bump` advances them, and `lockfile_platforms` in `.mise/config.toml` names the platforms; commit both) |
| colors, fonts, theme names | `DESIGN.md` first, then the files its Colors table names |

- Add a new tool to the lowest module that needs it, as `"latest"`. The exception is a desktop app that is a single release file: an `http:` tool pinned to a version and a SHA-256 (per platform for Obsidian, Vicinae and Ferdium; HackGen is one zip for both; [how to update](docs/guidance.md#update-a-pinned-desktop-app)).
- Every module is for a machine role, and the desktop is part of the base, so a GUI package goes in `mise-config/config.toml` (or `config.full.toml` for the toolbox).
- `home/.profile` is shared by bash and zsh: keep it POSIX. It sets environment variables and `PATH`, then sources the optional `profile.local`, and starts no program.
- A new eval'd tool init in `.zshrc`/`.bashrc` goes through `_djd_init` (cached), not a bare `eval "$(tool init)"`, unless its output embeds per-shell state such as `PATH` (`mise activate`, the one init that stays uncached).
- A new zsh plugin is a `[plugins.<name>]` entry in `home/.config/sheldon/plugins.toml` with a full commit `rev` and `apply = ["defer"]` (`["PATH", "defer"]` when its `bin` directory has to be on `PATH`, as for autojump). An alias is a mise `[shell_alias]` when it replaces a command, and a zsh-abbr abbreviation when it is a shortcut; nothing else defines one.
