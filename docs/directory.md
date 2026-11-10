# Directory

Where each file lives, which names are allowed, and which paths never enter the repository. [architecture.md](architecture.md) explains the choices, and [tech.md](tech.md) lists what the files declare.

## Layout

The tree shows the main parts. `git ls-files | cut -d/ -f1 | sort -u` lists every top-level entry.

```
install.sh              entry point: checks for Ubuntu 26.04, links ~/.dotfiles and ~/.config/mise, installs mise, runs djd tasks
Makefile                make <task> runs mise run <task>, with a few exceptions
.mise/                  the repo's own mise project, separate from mise-config/
  config.toml           repo tasks and the tools each task declares
  mise.lock, .mise/locks/  those tools pinned, with checksums, and the npm dependency graph (`mise lock` writes locks/ in the .mise/ of the project root)
  tasks/                repo file tasks: lint/, build, test/ (_default, offline, desktop, vm), ci
.actrc                  act runner images for mise run ci
LICENSE, .editorconfig, .shellcheckrc  license, editor settings, shellcheck settings
README.md, SECURITY.md  the entry page, and the security policy with the hardening and its limits
AGENTS.md               rules for coding agents, where each kind of change goes, verification commands
DESIGN.md               design tokens in the google-labs-code/design.md format
ROADMAP.md, CHANGELOG.md  what is planned, by horizon, and what each release changed
llms.txt                index of the docs for language-model readers
.env.example            the variable names for the agent providers and tokens, with no values
docs/                   requirements, architecture, problems, tech, directory, references, testing, maintenance and guidance, one .md each
mise-config/            linked as ~/.config/mise, the global config
  config.toml           base module: settings, core tools, base apt packages, locale, login shell, dotfile group home, the sheldon tool
  config.<module>.toml  the modules agent, server, full, warp, and secrets
  tasks/djd/            the djd commands, as global file tasks
  hooks/                dotfile-conflicts, server-post-packages, server-pre-dotfiles, sshd-keys-only, desktop-final and sheldon-lock: hook scripts that are too long for an inline [bootstrap.hooks] string; sshd-keys-only is not a hook of its own but the check that server-pre-dotfiles and `djd doctor` both run
home/                   dotfile group home, symlinked file by file into ~ (home/.config/pi and home/.config/omp hold the pi and omp config)
tests/                  tree.sh, tree-check.sh, vm-checks.sh, desktop-apps.sh, xsession-audio.sh, djd-module.sh, and server-hooks.sh
cloud-init/vm.yaml      the cloud-init file for incus and multipass
.devcontainer/          Dockerfile, Dockerfile.dockerignore, desktop-entrypoint.sh, compose.yaml, devcontainer.json, .env.example
.githooks/              pre-commit hook that runs gitleaks
.github/dependabot.yml  dependency updates
.github/workflows/      ci.yaml, tag.yaml, push.yaml, full-weekly.yaml, docs.yaml
```

`tests/tree.sh` writes the tracked and unignored files as a tar stream, judged by the repository's own `.gitignore` alone: the git configuration and the global ignore file of the machine have no effect, and a nested git repository is left out whole. `mise run ci`, `test:vm`, `test:offline`, and the no-trust flow in [AGENTS.md](../AGENTS.md) use it. `tests/vm-checks.sh` holds the assertions that `test:vm` runs inside the VM, and it refuses to run anywhere else (see `DJD_TEST_VM`). [testing.md](testing.md#test-map) maps each test script to the task that runs it.

## Allowed names and forbidden paths

| Kind of file | Where, and under what name |
| --- | --- |
| Global mise config | `mise-config/`. A mise project file or a `mise/` or `.config/mise/` directory at the top of the checkout would make mise treat the checkout itself as a project config, so none exists. |
| Repo tasks, their tools and lock | `.mise/` only: `tasks/<name>`, `config.toml` and the lock beside it. The tasks, the config and the lock do not live at the root. |
| Modules | `mise-config/config.<module>.toml` for `agent`, `server`, `full`, `warp` and `secrets`. The desktop is part of `config.toml`, so there is no `config.desktop.toml`. |
| Dotfiles | `home/`, under the literal name they have in `~`. |
| Hooks and djd commands | `mise-config/hooks/<name>` and `mise-config/tasks/djd/<name>`, both executable bash. |
| Tests | `tests/<name>.sh` (every offline test has a `# Contract` header), named in the layout above and run by a task. |
| Workflows | `.github/workflows/<name>.yaml`; a `*.yml` fails lint. |
| Docs | `docs/<name>.md` for the nine names above. There is no `README.md` inside `docs/`. Root Markdown is `README.md`, `AGENTS.md`, `SECURITY.md`, `DESIGN.md`, `ROADMAP.md` and `CHANGELOG.md`. |

These paths never enter the repository, and `.gitignore` enforces most of them:

- `.env` and `.env.*`, except `.env.example`; `.secrets` and `.vars` (act); `*.local.toml` and `*.local`; `age.txt`, `*.pem`, `*.key`, `auth.json`, `gh/hosts.yml` and `rclone/rclone.conf`.
- The pi and omp model lists (`models.json` and `models.yml` under `home/.config/`): they hold a Cloudflare account ID in their base URLs. They stay in `~/.config`.
- `home/.config/omp/profiles/*/agent/config.yml.lock`, which omp creates at run time.
- A `passwd:` entry in a cloud-init file, and a plaintext value in `mise-config/config.secrets.toml`.
- `node_modules/` and `.DS_Store`.

## XDG locations

The shell files and tools put their files in these places. [architecture.md](architecture.md#files-follow-xdg-where-the-tool-allows) explains the choices.

| Kind | Location | Written by |
| --- | --- | --- |
| Configuration | `~/.config`, with `~/.config/zsh` as `ZDOTDIR`, `~/.config/npm/npmrc` for npm, and `~/.config/djd` for `profile.local`, `bashrc.local`, and `age.txt` | the dotfile deployment, `djd secret`, npm |
| History | `$XDG_STATE_HOME`: `zsh/history`, `bash/history`, `lesshst`, `python_history`, `node_repl_history`, `djd/sshd-dropin`, the stamp that makes `hooks/server-pre-dotfiles` reload sshd only when the drop-in changed, and `djd/xrdp-restart`, the stamp that makes `hooks/desktop-final` restart xrdp once per change | `.zshrc`, `.bashrc`, `.profile`, less, `hooks/server-pre-dotfiles`, `hooks/desktop-final` |
| Cache | `$XDG_CACHE_HOME`: `zsh/zcompdump-<version>`, `zsh/zcompcache`, `zsh/init/`, `bash/init/`, `npm/`, `bun/`, and `fast-syntax-highlighting/` (or `fsh/`, when the first is not writable) | `.zshrc`, `.bashrc`, npm, bun, fast-syntax-highlighting |
| Data | `$XDG_DATA_HOME`: `mise/` with the shims, `sheldon/` with the zsh plugin checkouts and `plugins.lock`, `fonts/`, `applications/` and `icons/` (the Zed and Zen menu entries, and in the Docker image Brave's), and `cargo/` and `rustup/` (the `full` module) | mise, the `postinstall` of hackgen, zed, and zen, the Dockerfile |
| Executables | `~/.local/bin`, which holds `djd` and the mise binary that `install.sh` installs | the dotfile deployment, `install.sh` |

less picks `$XDG_STATE_HOME/lesshst` itself when that directory exists, and falls back to `~/.local/state/lesshst`, then `~/.lesshst`. `~/.local/state` always exists on a mise machine, because mise creates `state/mise` there. fast-syntax-highlighting runs `curl` the first time it loads, in the deferred source of `.zshrc`, to download `secondary_theme.zsh` into its cache directory.

The `agent` module sets `NPM_CONFIG_CACHE`, `NPM_CONFIG_USERCONFIG`, and `BUN_INSTALL_CACHE_DIR` in the `[env]` table of `config.agent.toml`. mise shims apply them to any shimmed program, including one started from `docker exec` or `sh -c`, and the image build applies them too. The same table turns telemetry off with `PI_TELEMETRY=0`, which pi reads, and `DO_NOT_TRACK=1`, which skills reads. bun reads it too, but only to stop crash reports, which it sends by default on macOS and Windows and not on Linux. omp does not read it, and its only telemetry is an OTLP export that sends nothing until `OTEL_*` endpoints are set.

These files stay outside the XDG directories. A session in the image in October 2026 that ran bash, zsh, npm, bun, gpg, omp, pi, python, node, and vim created every entry from `~/.gnupg` down. The first four rows are files that the repository or the system places there on purpose.

| Path | Reason |
| --- | --- |
| `~/.profile`, `~/.bash_profile`, `~/.bashrc` | bash reads only these paths. |
| `~/.zshenv` | zsh reads it before `ZDOTDIR` is set. |
| `~/.xsession` | `/etc/X11/Xsession` hard-codes it. |
| `~/.dotfiles` | It is the default `dotfiles.root` of mise, and `install.sh` clones there. |
| `~/.gnupg` | A `GNUPGHOME` export in `.profile` would reach login shells and not `docker exec`, which would then use another keyring. |
| `~/.omp`, `~/.pi` | omp and pi keep their state there when the `agent` module is not selected. With it, both keep their state under `~/.config/pi` and `~/.config/omp`. |
| `~/.viminfo` | A `~/.config/vim/vimrc` with `viminfofile` can move it. The repository does not ship one. |
| `~/.Xauthority`, `~/.ICEauthority`, `~/.dbus`, `~/.xsession-errors`, `~/.xorgxrdp.*.log` | The X, session-manager and xrdp sessions of the desktop write them, and the programs take no XDG path. They appear after the first RDP login. |
| `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Music`, `~/Pictures`, `~/Public`, `~/Templates`, `~/Videos` | `xdg-user-dirs` creates them at the first XFCE login. Their location is `~/.config/user-dirs.dirs`, which is an XDG path; the directories themselves sit in `~` by design of that specification. |

herdr keeps sockets and logs in `~/.config/herdr`, and micro keeps `buffers/` and `bindings.json` in `~/.config/micro`. Both directories are inside the XDG configuration directory, but they hold state.
