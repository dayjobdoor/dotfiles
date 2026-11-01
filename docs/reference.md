# Reference

Lookup tables for the repository. [architecture.md](architecture.md) explains the reasons behind them.

## Layout

The tree shows the main parts. `git ls-files | cut -d/ -f1 | sort -u` lists every top-level entry.

```
install.sh              entry point: checks for Ubuntu 26.04, links ~/.dotfiles and ~/.config/mise, installs mise, runs djd tasks
Makefile                make <task> runs mise run <task>, with a few exceptions
mise.toml, mise.lock    repo tasks and the tools each task declares, pinned in mise.lock and in .mise/locks/
mise-tasks/             repo file tasks: lint/, build, test/, ci
.actrc                  act runner images for mise run ci
DESIGN.md               design tokens in the google-labs-code/design.md format
mise-config/            linked as ~/.config/mise, the global config
  config.toml           base module: settings, core tools, base apt packages, locale, login shell, dotfile group home
  config.<module>.toml  the modules agent, server, desktop, full, and secrets
  tasks/djd/            the djd commands, as global file tasks
  hooks/                hook scripts that are too long for an inline [bootstrap.hooks] string, and the helpers they share
home/                   dotfile group home, symlinked file by file into ~
agent/                  dotfile group agent: the global AGENTS.md of pi and omp
desktop/                dotfile group desktop: .xsession, fcitx5, ghostty, and zed
agentos/                agentOS export and boot check
tests/                  tree.sh, vm-checks.sh, desktop-apps.sh, and xsession-audio.sh
cloud-init/             cloud-init files for incus, multipass, and OrbStack
.devcontainer/          Dockerfile, desktop entrypoint, compose.yaml, devcontainer.json
.githooks/              pre-commit hook that runs gitleaks
.github/workflows/      ci.yaml, tag.yaml, push.yaml, full-weekly.yaml
```

`tests/tree.sh` writes the tracked and unignored files as a tar stream. `mise run ci`, `test:vm`, and the no-trust flow in [AGENTS.md](../AGENTS.md) use it. `tests/vm-checks.sh` holds the assertions that `test:vm` runs inside the VM.

## Modules

A module is the file `mise-config/config.<module>.toml`. `djd module add` and `djd module remove` write the selection to `~/.config/mise/miserc.local.toml` as `env = [...]`, in the order `agent server desktop full secrets`.

| Module | apt packages | mise tools | Runs in |
| --- | --- | --- | --- |
| base, from `config.toml` | `ca-certificates curl git zsh sudo locales tzdata less vim unzip zip tree sqlite3 openssh-client gnupg fastfetch make` | `usage starship sheldon zoxide fzf ripgrep fd bat lsd sd jq yq delta gh lazygit jj jj-starship bottom micro herdr shellcheck shfmt` | every machine |
| `agent` | `build-essential pkg-config libssl-dev` | `node` at the lts channel, `bun`, `python`, `uv`, `pi`, `omp`, `skills` | sandbox image, desktop image, VMs |
| `server` | `openssh-server avahi-daemon ufw docker.io docker-compose-v2 docker-buildx` | `lazydocker` | VMs |
| `desktop` | `xfce4 xfce4-terminal xfce4-screenshooter xfce4-taskmanager xfce4-clipman-plugin xfce4-xkb-plugin xrdp xorgxrdp pipewire pipewire-pulse wireplumber pipewire-module-xrdp pulseaudio-utils dbus-x11 fcitx5-mozc language-pack-ja language-pack-ja-base manpages-ja fonts-noto-cjk fonts-noto-color-emoji ghostty brave-browser libasound2t64 mesa-vulkan-drivers xsel xdotool` | `zed` and `zen`, both from GitHub releases | desktop image, VMs |
| `full`, which requires `agent` | 33 packages, counted in the section below | 181 tools | opt-in, and the weekly CI |
| `secrets` | none | none | machines you own, never sandboxes |

### Files that modules manage

Base:

- The dotfile group `home`.
- The login shell `zsh`.
- `/etc/locale.conf` set to `C.UTF-8`.

`agent`:

- The dotfile group `agent`: `~/.pi/agent/AGENTS.md` and `~/.omp/agent/AGENTS.md`, the global instructions that pi and omp each read from their own agent directory. The two files have the same content.
- `[env]` values that every program started through a mise shim sees, in any shell type: the npm and bun locations, `PI_TELEMETRY=0`, and `DO_NOT_TRACK=1`. A plain `sh -c 'echo $DO_NOT_TRACK'` prints nothing, because `sh` is not a shim.
- `pi` and `omp` are the exception to `minimum_release_age = "3d"` (`minimum_release_age_excludes` in `config.agent.toml`): they install on the day they release, because they release often and the owner wants each release at once.

`server`:

- The sshd drop-in `/etc/ssh/sshd_config.d/10-djd.conf` allows keys only and denies root login. The `pre-dotfiles` hook `hooks/server-pre-dotfiles` checks it.
- ufw denies incoming traffic, limits 22/tcp, and allows 3389/tcp from private networks only. No mDNS rule exists, because `before.rules` of ufw already accepts multicast.
- `/etc/docker/daemon.json` binds published ports to `127.0.0.1` by default, through `ip` and `default-network-opts`. docker restarts when the file changes.
- The `post-packages` hook adds the user to the `docker` group.

`desktop`:

- `/etc/locale.conf` is set to `ja_JP.UTF-8`, which overrides base. `/etc/default/locale` links to it.
- The dotfile group `desktop`. Its `~/.xsession` starts `pipewire`, `wireplumber`, and `pipewire-pulse` inside the session's D-Bus when no PipeWire server answers `pw-cli info 0`, which is the case in the Docker image. The desktop does not wait for them. A background shell polls for pipewire 600 times, 0.1 s apart, because wireplumber exits when it starts first. It then starts `pipewire-pulse` and keeps `wireplumber` running: it starts it again after it dies, and gives up after five runs in a row that each lasted under 30 s. When pipewire never answers, the shell prints one line to `~/.xsession-errors` and starts neither. `startxfce4` runs without `exec`, and when the desktop exits the script kills the server it started, the background shell, and their daemons. Logging out would otherwise leave them running, and the supervisor would start a wireplumber against the dead session bus. A session that only disconnects keeps running and loses nothing. A server that already answered is never touched. A socket file that a dead server left behind does not count. In a VM, systemd's socket-activated server should answer the check, so that nothing starts twice. That case was not tested in a VM.
- Audio over RDP comes from the package `pipewire-module-xrdp`. An XDG autostart entry of that package loads `xrdp-sink` and `xrdp-source` into the session's PipeWire and makes them the defaults through `pactl`, from `pulseaudio-utils`.
- The four required apps. `ghostty` comes from the Ubuntu archive. `brave-browser` comes from Brave's apt repository, declared in `[bootstrap.apt.sources.brave-browser]` with `suites = "stable"` and three pinned key fingerprints. `zed` and `zen` are `github:` tools at `latest`, with a per-platform `asset_pattern`. [architecture.md](architecture.md#the-desktop-apps-each-carry-a-trust-anchor) explains what verifies each one.
- Each app has an XFCE menu entry. Brave and ghostty use the entries of their packages. The `postinstall` of `zed` and `zen` writes `~/.local/share/applications/dev.zed.Zed.desktop` and `zen.desktop` with `Exec` on the mise shim, and installs the icon. `filter_bins = "zen"` keeps `zen-bin`, `updater`, `pingsender`, and `gfxtest` off `PATH`.
- The Docker image, not the module, writes a user-level `~/.local/share/applications/brave-browser.desktop` that adds `--no-sandbox` to every `Exec` line.
- `tests/desktop-apps.sh` checks all four apps. `mise-tasks/test/desktop` runs it in the image with `DJD_APPS_LAUNCH=1`, which also starts Brave and Zen headless and opens a window for ghostty and Zed inside the RDP session, and `tests/vm-checks.sh` runs it in the VM without the variable.
- The `final` hook purges light-locker, xscreensaver, im-config, and the pulseaudio daemon, which would claim the pulse socket next to pipewire-pulse. It sets `security_layer=tls` in `/etc/xrdp/xrdp.ini` and `AllowRootLogin=false` in `/etc/xrdp/sesman.ini`, and it prints a reminder that xrdp keeps the old values until it restarts. It then installs HackGen NF with curl, from a pinned version and SHA-256.
- `/etc/apt/apt.conf.d/90djd-conffiles` sets `--force-confdef` and `--force-confold` for every apt run on the machine, so `djd update` keeps the edited xrdp conffiles and never stops at dpkg's conffile prompt. A new maintainer version lands beside the file as `*.dpkg-dist`.
- The dotfile `desktop/.config/zed/settings.json` turns Zed's telemetry and auto-update off. Zed may rewrite the file through its symlink.
- Two limits of the audio start remain. `pipewire-module-xrdp` loads its module from a background `pw-cli`, so each login leaves one idle `pw-cli` behind. Nothing restarts `pipewire-pulse` or the pipewire server when either dies, and a `wireplumber` that dies five times in a row within 30 s of starting stays off until the next login.

`secrets`: `[env]` values stored as age ciphertext.

### Size of the full module

The `full` module has 33 apt packages. 21 are CLI packages, such as build libraries and network tools. 12 are GUI packages, such as GTK and WebKit development libraries, flatpak, and mpd, and they install only when `desktop` is selected too. The 181 tools were carried over from the repository that this one started from ([history.md](history.md)). ruby comes from mise only, and sqlite3 and fastfetch come from the base apt list. dotnet is commented out because its installer rejects 26.04, and vegeta and taskctl install on amd64 only.

These commands regenerate the counts. They print 181 tools, 33 apt packages, and 12 GUI packages.

```sh
awk '/^\[tools\]/{t=1;next} /^\[/{t=0} t&&/^"?[a-z]/' mise-config/config.full.toml | wc -l
awk '/^\[bootstrap.packages\]/{p=1;next} /^\[/{p=0} p&&/^"apt:/' mise-config/config.full.toml | wc -l
grep -c 'env = "desktop"' mise-config/config.full.toml
```

The module needs more than 10 GB of free disk. 155 of its tools used 7.5 GB of installs plus 2.5 GB of cache, measured in October 2026 on an arm64 Mac running OrbStack.

## djd commands

`home/.local/bin/djd` routes `djd <cmd> [args]` to `mise run djd:<cmd> [args]`. It runs from `$HOME` with `MISE_TASK_RUN_AUTO_INSTALL=false` and `LC_ALL=C.UTF-8`. Plain `djd` lists the commands.

| Command | Does |
| --- | --- |
| `djd apply [flags]` | Runs `mise bootstrap --yes --update` and clears the shell init caches. It moves no file itself: real files that a dotfile would replace are moved aside by the `pre-dotfiles` hook (see Bootstrap phases and hooks). |
| `djd update` | Runs `git fetch` and `git merge --ff-only @{u}` when the checkout is a git repository, then `mise self-update`, then `djd apply --upgrade`. A dirty file that the update does not touch stays. |
| `djd status` | Prints the checkout path and commit, the selected modules, and `mise bootstrap status`. |
| `djd doctor` | Checks Ubuntu 26.04 (`VERSION_ID`), the `~/.config/mise` link, the zsh login shell, `bootstrap status --missing`, and `dot status --missing`, and lists each dotfile that differs from the checkout. Hooks are imperative and `bootstrap status` cannot see what they enforce, so it also checks them: with `server` selected, that sshd is keys-only (`hooks/sshd-keys-only`); with `desktop` selected, `security_layer=tls` in `xrdp.ini` and `AllowRootLogin=false` in `sesman.ini`, each on its own line. With the `secrets` module selected, it also checks that `~/.config/djd/age.txt` exists, has no group or other permission bits (mode 0600 and 0400 pass), and decrypts every value. Exits with code 1 on any failure. |
| `djd module list` | Prints each module and whether it is selected. |
| `djd module add <module>...` | Selects the modules and applies the selection. `full` selects `agent` too. Prints a warning when `desktop` is selected without `server`, because only `server` carries the RDP firewall rules. |
| `djd module remove <module>...` | Unselects the modules, unapplies their files and dotfile groups, and applies what remains, so base declarations such as the locale come back. A module that was never applied causes no error. It refuses to remove `agent` while `full` is selected (exit 2). `remove desktop` also deletes `/etc/apt/sources.list.d/mise-brave-browser.sources`, because mise never removes an apt source; the packages stay. |
| `djd secret keygen` | Creates the age key at `~/.config/djd/age.txt`. |
| `djd secret set <name>` | Encrypts a prompted value into the secrets module. |

Only `djd module` and `djd secret` declare arguments, so only their `--help` lists them. `djd apply`, `djd update`, and `djd status` pass extra flags to the mise command they run, as in `djd apply --upgrade`. `djd doctor` ignores them. The `djd` wrapper and `install.sh` unset your own `MISE_ENV`, which would otherwise replace the module selection.

## Make targets

`make <task>` runs `mise run <task>`, and `make <task> ARGS=<args>` passes arguments. `make build ARGS=desktop` runs `mise run build desktop`. `make help` lists the tasks. Two groups differ.

- `make init` runs `./install.sh $(ARGS)`. It runs before mise exists, so the machine needs make. A fresh Ubuntu cloud image can lack it, and `sudo apt-get install make` adds it. `./install.sh` needs no make, and the base apt list installs make for later runs.
- `make apply`, `make update`, `make status`, `make doctor`, `make module`, and `make secret` run `djd`, so they keep its locale and its working directory.

## Bootstrap phases and hooks

`mise bootstrap` applies its phases in this observed order: packages, the `post-packages` hook, system files, services, the firewall, the `pre-dotfiles` hook, dotfiles, the `pre-user` hook, the login shell, tools, and the `final` hook. A standalone `mise dot apply` also runs the `pre-dotfiles` and `post-dotfiles` hooks. mise runs the hooks of every selected module in order, base first, and only when their part runs, so `djd apply --dry-run`, `--skip dotfiles`, and `--only` without `dotfiles` move no file.

| Hook | Declared by | Does |
| --- | --- | --- |
| `pre-user` | base | Switches the login shell to zsh through sudo. |
| `post-packages` | `server` | Adds the user to the `docker` group. |
| `pre-dotfiles` | base, `agent`, `desktop` | Run `hooks/dotfile-conflicts <group>` for the dotfile group `home`, `agent`, or `desktop`. It deletes a real file that equals its `/etc/skel` copy, and moves any other real file that a dotfile would replace to `<file>.djd-backup-<time>`. |
| `pre-dotfiles` | `server` | Runs `hooks/server-pre-dotfiles`, which fails the apply unless the sshd drop-in is in effect (`hooks/sshd-keys-only` makes the check, and `djd doctor` shares it). It runs after the base and `agent` hooks, so an apply that fails here can leave files moved aside. |
| `final` | `desktop` | Runs `hooks/desktop-final`. |

## Shell startup files

| File | Read by | Does |
| --- | --- | --- |
| `~/.profile` | bash login shells, zsh through `.zshenv`, and agentOS when sourced explicitly | Sets the XDG directories, `DJD_DIR`, `PATH` with the mise shims and `~/.local/bin`, `LANG`, `TZ` with the default `Asia/Tokyo`, `EDITOR`, and the history files `LESSHISTFILE`, `PYTHON_HISTORY`, and `NODE_REPL_HISTORY`. Then reads `~/.config/djd/profile.local`, which it tests with `-f` because the agentOS shell says `[ -r <missing file> ]` is true. It is POSIX and has no side effects. |
| `~/.zshenv` | every zsh | Sets `skip_global_compinit=1`, so that the `compinit` of `/etc/zsh/zshrc` does not drop `.zcompdump` into `ZDOTDIR`. Sets `ZDOTDIR=~/.config/zsh` and sources `.profile`. |
| `~/.config/zsh/.zshenv` | every zsh that starts with `ZDOTDIR` already exported, which is a nested shell | Sources `~/.zshenv`, so nested shells load `.profile` too. |
| `~/.config/zsh/.zprofile` | zsh login shells | Starts herdr on a real terminal. It does not start herdr when `DJD_NO_MUX` is set, as the Docker images do, nor inside herdr, nor in an IDE terminal. |
| `~/.config/zsh/.zshrc` | interactive zsh | Sets up history, completion, starship, zoxide, fzf, atuin when installed (after fzf, so atuin owns Ctrl-R), sheldon, `mise activate`, and `.functions`, and reads `$ZDOTDIR/.zshrc.local`. Its `chpwd` hook runs `ls -la` in the top-level shell only. |
| `~/.config/zsh/.zlogin` | zsh login shells | Prints an interactive banner with fortune and cowsay, when installed. Prints a second banner with figlet and lolcat, when installed. A login shell that runs a command prints nothing. |
| `~/.config/zsh/.zlogout` | interactive zsh login shells, on exit | Runs fastfetch, or prints a short banner when it is missing. `zsh -lc` does not read it. |
| `~/.bash_profile` and `~/.bashrc` | bash | Source `.profile`, then run the interactive-only setup: history (appended, not overwritten), starship, zoxide, omp completions, and `mise activate` last, because `starship init bash` overwrites `PROMPT_COMMAND` and would drop mise's hook. |

## Environment variables

| Variable | Default | Effect |
| --- | --- | --- |
| `DJD_DIR` | `~/.dotfiles` | Path of the checkout, exported by `.profile` for the shells. It is not an override: `install.sh` and the djd tasks always use `~/.dotfiles`, because mise reads `~/.config/mise` and `dotfiles.root` there. |
| `DJD_REPO` | the GitHub URL of this repository | Repository that `install.sh` clones. |
| `MISE_VERSION` | the pinned release | mise release that `install.sh` installs. |
| `DJD_BOOTSTRAP_FLAGS` | empty | Extra flags that `djd apply` passes to `mise bootstrap`. The Docker build passes `--skip tools,final-hook,dotfiles`, `--only tools,final-hook`, and `--only dotfiles`. |
| `DJD_NO_MUX` | unset | When set, `.zprofile` does not start herdr. The Docker images set it. |
| `DJD_MODULES` | `agent` | Build argument of the Dockerfile. It lists the modules that a flavor installs. |
| `DJD_REVISION` | `unknown` | Build argument of the Dockerfile. `mise run build` sets it from `git describe --always --dirty` (a build from a modified tree ends in `-dirty`, and it is `unknown` without git), `push.yaml` sets the full commit SHA, and the builds of `compose.yaml` and `devcontainer.json` leave it unset. `djd status` prints it when the checkout has no `.git`. |
| `DJD_KEEP_VM` | unset | When set, `test:vm` keeps its VM after the run. |
| `DJD_APPS_LAUNCH` | unset | When `1`, `tests/desktop-apps.sh` also starts the four apps. `test:desktop` sets it. |
| `RDP_PORT` | `33389` | Host port that `compose.yaml` publishes on `127.0.0.1` for RDP. Set it in `.devcontainer/.env`. |
| `PASSWORD` | required | RDP password of the desktop container. Set it in `.devcontainer/.env`. |

[SECURITY.md](../SECURITY.md#local-overrides) lists the machine-local override files.

## XDG locations

The shell files and tools put their files in these places. [architecture.md](architecture.md#files-follow-xdg-where-the-tool-allows) explains the choices.

| Kind | Location | Written by |
| --- | --- | --- |
| Configuration | `~/.config`, with `~/.config/zsh` as `ZDOTDIR`, `~/.config/npm/npmrc` for npm, and `~/.config/djd` for `profile.local`, `bashrc.local`, and `age.txt` | the dotfile deployment, `djd secret`, npm |
| History | `$XDG_STATE_HOME`: `zsh/history`, `bash/history`, `lesshst`, `python_history`, `node_repl_history`, and `djd/sshd-dropin`, the stamp that makes `hooks/server-pre-dotfiles` reload sshd only when the drop-in changed | `.zshrc`, `.bashrc`, `.profile`, `hooks/server-pre-dotfiles` |
| Cache | `$XDG_CACHE_HOME`: `zsh/zcompdump-<version>`, `zsh/zcompcache`, `zsh/init/`, `bash/init/`, `npm/`, `bun/` | `.zshrc`, `.bashrc`, npm, bun |
| Data | `$XDG_DATA_HOME`: `mise/` with the shims, the sheldon plugin clones, `fonts/`, `applications/` and `icons/` (the Zed and Zen menu entries, and in the Docker image Brave's), and `cargo/` and `rustup/` (the `full` module) | mise, sheldon, `hooks/desktop-final`, the `postinstall` of zed and zen, the Dockerfile |
| Executables | `~/.local/bin`, which holds `djd` and the mise binary that `install.sh` installs | the dotfile deployment, `install.sh` |

The `agent` module sets `NPM_CONFIG_CACHE`, `NPM_CONFIG_USERCONFIG`, and `BUN_INSTALL_CACHE_DIR` in the `[env]` table of `config.agent.toml`. mise shims apply them to any shimmed program, including one started from `docker exec` or `sh -c`, and the image build applies them too. The same table turns telemetry off with `PI_TELEMETRY=0`, which pi reads, and `DO_NOT_TRACK=1`, which skills reads. bun reads it too, but only to stop crash reports, which it sends by default on macOS and Windows and not on Linux. omp does not read it, and its only telemetry is an OTLP export that sends nothing until `OTEL_*` endpoints are set.

These files stay outside the XDG directories. A session in the sandbox image in October 2026 that ran bash, zsh, npm, bun, gpg, omp, pi, python, node, and vim created every entry from `~/.gnupg` down. The first four rows are files that the repository or the system places there on purpose.

| Path | Reason |
| --- | --- |
| `~/.profile`, `~/.bash_profile`, `~/.bashrc` | bash reads only these paths. |
| `~/.zshenv` | zsh reads it before `ZDOTDIR` is set. |
| `~/.xsession` | `/etc/X11/Xsession` hard-codes it. |
| `~/.dotfiles` | It is the default `dotfiles.root` of mise, and `install.sh` clones there. |
| `~/.gnupg` | A `GNUPGHOME` export in `.profile` would reach login shells and not `docker exec`, which would then use another keyring. |
| `~/.omp`, `~/.pi` | omp and pi keep their state there. The `agent` dotfile group also links `AGENTS.md` into `~/.pi/agent` and `~/.omp/agent`. |
| `~/.viminfo` | A `~/.config/vim/vimrc` with `viminfofile` can move it. The repository does not ship one. |

herdr keeps sockets and logs in `~/.config/herdr`, and micro keeps `buffers/` and `bindings.json` in `~/.config/micro`. Both directories are inside the XDG configuration directory, but they hold state.

## agentOS

`mise run agentos:export` writes `dist/agentos/bundle.json` with the files, the registry packages, and the environment. `mise run agentos:boot` builds the same bundle in memory, boots a VM with it through `@rivet-dev/agentos-core` 0.4.6 with the guest network denied, and runs the `CHECKS` in `agentos/boot.mjs`. Every check needs exit 0, the expected stdout, and an empty stderr. Two checks differ. `git commit` prints `fork failed` in the guest and succeeds, and the network check needs a non-zero exit with `Could not resolve host`.

| Works in agentOS | Does not work |
| --- | --- |
| `~/.profile` when sourced with `sh -c '. "$HOME/.profile"; ...'`: the XDG directories, `DJD_DIR`, `LANG`, and `TZ` | mise and its shims, zsh, sheldon, starship |
| `~/.config/git/config`, `ignore`, and `commit.template`, plus `agentos/gitconfig` as `~/.gitconfig`, which sets the pager to `cat`, empties the diff filter, and resets the GitHub credential helpers, because the guest has no delta, gh, or less | apt, systemd, ufw, docker |
| the registry WASM tools git, curl, jq, ripgrep, fd, yq, tree, sqlite3, unzip, and zip | any Linux ELF binary, and `vim`, because its 0.4.6 package installs no commands |

Verified on 0.4.6, the release that `agentos/package.json` pins:

- `exec` and `execFile` shells read no startup files. `sh -l`, `bash --login`, and `bash -l -i` all skip `/etc/profile` and `~/.profile`, so callers source `~/.profile` themselves.
- Setting `BASH_ENV` or `ENV` in `environment` breaks every shell with the error `not yet implemented: load config from $ENV/BASH_ENV`. The export keeps the base environment of agentos-core, except `PAGER`, which is `cat` because the guest has no `less`.
- `[ -r <missing file> ]`, `[ -x ... ]`, and `[ -w ... ]` return true in the guest, while `-f` and `-e` return false. Before `.profile` used `-f`, sourcing it printed `failed to source file` and returned 1 in every guest.
- Registry packages download on the host from the locked URLs on `releases.rivet.dev`, so the guest needs no network for them. The default download timeout of 30 s fails on slow links, so the boot raises it to 5 minutes. A separate 60 s wait for package acquisition has no option in JavaScript, so a slow link can still fail the boot with `acquisition waiter exceeded 60000ms`. Run it again.
- `mise run agentos:lock` rewrites `agentos/software.lock.json` from the live manifest of the release that `agentos/package.json` pins. Review the diff, commit it, and run `mise run agentos:boot`.
- The registry `jq` is jaq, and the registry `yq` is its own build. `yq --version` hangs for about 15 s, so the boot pipes a document through `yq '.a'` instead.

## Docker images

[architecture.md](architecture.md#docker-images-are-one-dockerfile-in-two-passes) explains how the Dockerfile builds them.

| Image | Modules | Use |
| --- | --- | --- |
| `ghcr.io/dayjobdoor/dotfiles:sandbox`, also tagged `latest`, `X.Y.Z`, and `X.Y` | `agent` | Agent sandbox and devcontainer. |
| `ghcr.io/dayjobdoor/dotfiles:desktop`, also tagged `X.Y.Z-desktop` and `X.Y-desktop` | `agent` and `desktop` | XFCE over RDP. `.devcontainer/compose.yaml` builds the same image locally and publishes it on `127.0.0.1:33389`. `mise run up` starts it. |
| `djd:full`, local only and not published | `agent` and `full` | The full toolbox. `mise run build full` builds it. `full-weekly.yaml` builds it weekly, runs `djd doctor` in it, and then runs `djd update && djd doctor`. |

Every image sets `DJD_NO_MUX=1` and puts the mise shims on `PATH`. The images that `mise run build` and `push.yaml` build also carry the commit in `DJD_REVISION`. Start the containers with `--init`, so that an init process reaps zombies. `compose.yaml` and `devcontainer.json` set it, and `mise run shell` passes it.
