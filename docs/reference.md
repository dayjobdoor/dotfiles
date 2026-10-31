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
  hooks/                hook scripts that are too long for an inline [bootstrap.hooks] string
home/                   dotfile group home, symlinked file by file into ~
desktop/                dotfile group desktop: .xsession, fcitx5, and ghostty
agentos/                agentOS export and boot check
tests/                  tree.sh, vm-checks.sh, and desktop-apps.sh
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
| `desktop` | `xfce4 xfce4-terminal xfce4-screenshooter xfce4-taskmanager xfce4-clipman-plugin xfce4-xkb-plugin xrdp xorgxrdp dbus-x11 fcitx5-mozc language-pack-ja language-pack-ja-base manpages-ja fonts-noto-cjk fonts-noto-color-emoji ghostty brave-browser libasound2t64 mesa-vulkan-drivers xsel xdotool` | `zed` and `zen`, both from GitHub releases | desktop image, VMs |
| `full`, which requires `agent` | 34 packages, counted in the section below | 183 tools | opt-in, and the weekly CI |
| `secrets` | none | none | machines you own, never sandboxes |

### Files that modules manage

Base:

- The dotfile group `home`.
- The login shell `zsh`.
- `/etc/locale.conf` set to `C.UTF-8`.

`server`:

- The sshd drop-in `/etc/ssh/sshd_config.d/10-djd.conf` allows keys only and denies root login. The `pre-dotfiles` hook `hooks/server-pre-dotfiles` checks it.
- ufw denies incoming traffic, limits 22/tcp, and allows 3389/tcp from private networks only. No mDNS rule exists, because `before.rules` of ufw already accepts multicast.
- `/etc/docker/daemon.json` binds published ports to `127.0.0.1` by default, through `ip` and `default-network-opts`. docker restarts when the file changes.
- The `post-packages` hook adds the user to the `docker` group.

`desktop`:

- `/etc/locale.conf` is set to `ja_JP.UTF-8`, which overrides base. `/etc/default/locale` links to it.
- The dotfile group `desktop`.
- The four required apps. `ghostty` comes from the Ubuntu archive. `brave-browser` comes from Brave's apt repository, declared in `[bootstrap.apt.sources.brave-browser]` with `suites = "stable"` and three pinned key fingerprints. `zed` and `zen` are `github:` tools at `latest`, with a per-platform `asset_pattern`. [architecture.md](architecture.md#the-desktop-apps-each-carry-a-trust-anchor) explains what verifies each one.
- Each app has an XFCE menu entry. Brave and ghostty use the entries of their packages. The `postinstall` of `zed` and `zen` writes `~/.local/share/applications/dev.zed.Zed.desktop` and `zen.desktop` with `Exec` on the mise shim, and installs the icon. `filter_bins = "zen"` keeps `zen-bin`, `updater`, `pingsender`, and `gfxtest` off `PATH`.
- The Docker image, not the module, writes a user-level `~/.local/share/applications/brave-browser.desktop` that adds `--no-sandbox` to every `Exec` line.
- `tests/desktop-apps.sh` checks all four apps. `mise-tasks/test/desktop` runs it in the image with `DJD_APPS_LAUNCH=1`, which also starts Brave and Zen headless, and `tests/vm-checks.sh` runs it in the VM without the variable.
- The `final` hook purges light-locker, xscreensaver, and im-config. It then installs HackGen NF with curl, from a pinned version and SHA-256.

`secrets`: `[env]` values stored as age ciphertext.

### Size of the full module

The `full` module has 34 apt packages. 22 are CLI packages, such as build libraries and network tools. 12 are GUI packages, such as GTK and WebKit development libraries, flatpak, and mpd, and they install only when `desktop` is selected too. The 183 tools come from budybye/dotfiles. dotnet is commented out because its installer rejects 26.04, and vegeta and taskctl install on amd64 only.

These commands regenerate the counts. They print 183 tools, 34 apt packages, and 12 GUI packages.

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
| `djd apply [flags]` | Moves conflicting real files aside as `*.djd-backup-<time>` and deletes untouched `/etc/skel` copies. Then runs `mise bootstrap --yes --update` and clears the shell init caches. |
| `djd update` | Runs `git fetch` and `git merge --ff-only @{u}` when the checkout is a git repository, then `mise self-update`, then `djd apply --upgrade`. A dirty file that the update does not touch stays. |
| `djd status` | Prints the checkout path and commit, the selected modules, and `mise bootstrap status`. |
| `djd doctor` | Checks Ubuntu, the `~/.config/mise` link, the zsh login shell, `bootstrap status --missing`, and `dot status --missing`. Lists each dotfile that differs from the checkout. With the `secrets` module selected, it also checks that `~/.config/djd/age.txt` exists, has mode 600, and decrypts every value. Exits with code 1 on any failure. |
| `djd module list` | Prints each module and whether it is selected. |
| `djd module add <module>...` | Selects the modules and applies the selection. `full` selects `agent` too. Prints a warning when `desktop` is selected without `server`, because only `server` carries the RDP firewall rules. |
| `djd module remove <module>...` | Unselects the modules, unapplies their files and dotfile groups, and applies what remains, so base declarations such as the locale come back. A module that was never applied causes no error. |
| `djd secret keygen` | Creates the age key at `~/.config/djd/age.txt`. |
| `djd secret set <name>` | Encrypts a prompted value into the secrets module. |

Only `djd module` and `djd secret` declare arguments, so only their `--help` lists them. The other commands pass extra flags to the mise command they run, as in `djd apply --upgrade`.

## Make targets

`make <task>` runs `mise run <task>`, and `make <task> ARGS=<args>` passes arguments. `make build ARGS=desktop` runs `mise run build desktop`. `make help` lists the tasks. Two groups differ.

- `make init` runs `./install.sh $(ARGS)`. It runs before mise exists, so the machine needs make. A fresh Ubuntu cloud image can lack it, and `sudo apt-get install make` adds it. `./install.sh` needs no make, and the base apt list installs make for later runs.
- `make apply`, `make update`, `make status`, `make doctor`, `make module`, and `make secret` run `djd`, so they keep its locale and its working directory.

## Bootstrap phases and hooks

`mise bootstrap` applies its phases in this observed order: packages, the `post-packages` hook, system files, services, the firewall, the `pre-dotfiles` hook, dotfiles, the `pre-user` hook, the login shell, tools, and the `final` hook. A standalone `mise dot apply` also runs the `pre-dotfiles` and `post-dotfiles` hooks. mise runs the hooks of every selected module in order, base first.

| Hook | Declared by | Does |
| --- | --- | --- |
| `pre-user` | base | Switches the login shell to zsh through sudo. |
| `post-packages` | `server` | Adds the user to the `docker` group. |
| `pre-dotfiles` | `server` | Runs `hooks/server-pre-dotfiles`, which fails the apply unless the sshd drop-in is in effect. |
| `final` | `desktop` | Runs `hooks/desktop-final`. |

## Shell startup files

| File | Read by | Does |
| --- | --- | --- |
| `~/.profile` | bash login shells, zsh through `.zshenv`, and agentOS when sourced explicitly | Sets the XDG directories, `DJD_DIR`, `PATH` with the mise shims and `~/.local/bin`, `LANG`, `TZ` with the default `Asia/Tokyo`, `EDITOR`, and the history files `LESSHISTFILE`, `PYTHON_HISTORY`, and `NODE_REPL_HISTORY`. Then reads `~/.config/djd/profile.local`, which it tests with `-f` because the agentOS shell says `[ -r <missing file> ]` is true. It is POSIX and has no side effects. |
| `~/.zshenv` | every zsh | Sets `skip_global_compinit=1`, so that the `compinit` of `/etc/zsh/zshrc` does not drop `.zcompdump` into `ZDOTDIR`. Sets `ZDOTDIR=~/.config/zsh` and sources `.profile`. |
| `~/.config/zsh/.zshenv` | every zsh that starts with `ZDOTDIR` already exported, which is a nested shell | Sources `~/.zshenv`, so nested shells load `.profile` too. |
| `~/.config/zsh/.zprofile` | zsh login shells | Starts herdr on a real terminal. It does not start herdr when `DJD_NO_MUX` is set, as the Docker images do, nor inside herdr, nor in an IDE terminal. |
| `~/.config/zsh/.zshrc` | interactive zsh | Sets up history, completion, starship, zoxide, fzf, sheldon, `mise activate`, and `.functions`. |
| `~/.config/zsh/.zlogin` | zsh login shells | Prints an interactive banner with fortune and cowsay, when installed. Prints a second banner with figlet and lolcat, when installed. A login shell that runs a command prints nothing. |
| `~/.bash_profile` and `~/.bashrc` | bash | Source `.profile`, then run the interactive-only setup. |

## Environment variables

| Variable | Default | Effect |
| --- | --- | --- |
| `DJD_DIR` | `~/.dotfiles` | Path of the checkout in `.profile` and in the djd tasks. `install.sh` always uses `~/.dotfiles`. |
| `DJD_REPO` | the GitHub URL of this repository | Repository that `install.sh` clones. |
| `MISE_VERSION` | the pinned release | mise release that `install.sh` installs. |
| `DJD_BOOTSTRAP_FLAGS` | empty | Extra flags that `djd apply` passes to `mise bootstrap`. The Docker build passes `--skip dotfiles` and `--only dotfiles`. |
| `DJD_NO_MUX` | unset | When set, `.zprofile` does not start herdr. The Docker images set it. |
| `DJD_MODULES` | `agent` | Build argument of the Dockerfile. It lists the modules that a flavor installs. |
| `DJD_REVISION` | `unknown` | Build argument of the Dockerfile. `mise run build` and `push.yaml` set it, and the builds of `compose.yaml` and `devcontainer.json` leave it unset. `djd status` prints it when the checkout has no `.git`. |
| `DJD_KEEP_VM` | unset | When set, `test:vm` keeps its VM after the run. |

[SECURITY.md](../SECURITY.md#local-overrides) lists the machine-local override files.

## XDG locations

The shell files and tools put their files in these places. [architecture.md](architecture.md#files-follow-xdg-where-the-tool-allows) explains the choices.

| Kind | Location | Written by |
| --- | --- | --- |
| Configuration | `~/.config`, with `~/.config/zsh` as `ZDOTDIR`, `~/.config/npm/npmrc` for npm, and `~/.config/djd` for `profile.local`, `bashrc.local`, and `age.txt` | the dotfile deployment, `djd secret`, npm |
| History | `$XDG_STATE_HOME`: `zsh/history`, `bash/history`, `lesshst`, `python_history`, `node_repl_history` | `.zshrc`, `.bashrc`, `.profile` |
| Cache | `$XDG_CACHE_HOME`: `zsh/zcompdump-<version>`, `zsh/zcompcache`, `zsh/init/`, `bash/init/`, `npm/`, `bun/` | `.zshrc`, `.bashrc`, npm, bun |
| Data | `$XDG_DATA_HOME`: `mise/` with the shims, the sheldon plugin clones, and `fonts/` | mise, sheldon, `hooks/desktop-final` |
| Executables | `~/.local/bin`, which holds `djd` | the dotfile deployment |

The `agent` module sets `NPM_CONFIG_CACHE`, `NPM_CONFIG_USERCONFIG`, and `BUN_INSTALL_CACHE_DIR` in the `[env]` table of `config.agent.toml`. mise shims apply them to every shell type, including `docker exec` and `sh -c`, and the image build applies them too.

These files stay outside the XDG directories. A session in the sandbox image in October 2026 that ran bash, zsh, npm, bun, gpg, omp, pi, python, node, and vim created every entry from `~/.gnupg` down. The first four rows are files that the repository or the system places there on purpose.

| Path | Reason |
| --- | --- |
| `~/.profile`, `~/.bash_profile`, `~/.bashrc` | bash reads only these paths. |
| `~/.zshenv` | zsh reads it before `ZDOTDIR` is set. |
| `~/.xsession` | `/etc/X11/Xsession` hard-codes it. |
| `~/.dotfiles` | It is the default `dotfiles.root` of mise, and `install.sh` clones there. |
| `~/.gnupg` | A `GNUPGHOME` export in `.profile` would reach login shells and not `docker exec`, which would then use another keyring. |
| `~/.omp`, `~/.pi` | omp and pi keep their state there. |
| `~/.viminfo` | A `~/.config/vim/vimrc` with `viminfofile` can move it. The repository does not ship one. |
| `~/.config/herdr`, `~/.config/micro` | herdr keeps sockets and logs in its config directory, and micro keeps `buffers/` and `bindings.json` in its own. |

## agentOS

`mise run agentos:export` writes `dist/agentos/bundle.json` with the files, the registry packages, and the environment. `mise run agentos:boot` builds the same bundle in memory, boots a VM with it through `@rivet-dev/agentos-core` 0.4.6 with the guest network denied, and runs the `CHECKS` in `agentos/boot.mjs`. Every check needs exit 0, the expected stdout, and an empty stderr. Two checks differ. `git commit` prints `fork failed` in the guest and succeeds, and the network check needs a non-zero exit with `Could not resolve host`.

| Works in agentOS | Does not work |
| --- | --- |
| `~/.profile` when sourced with `sh -c '. "$HOME/.profile"; ...'`: the XDG directories, `DJD_DIR`, `LANG`, and `TZ` | mise and its shims, zsh, sheldon, starship |
| `~/.config/git/config`, `ignore`, and `commit.template`, plus `agentos/gitconfig` as `~/.gitconfig`, which sets the pager to `cat`, empties the diff filter, and resets the GitHub credential helpers, because the guest has no delta, gh, or less | apt, systemd, ufw, docker |
| the registry WASM tools git, curl, jq, ripgrep, fd, yq, tree, sqlite3, unzip, and zip | any Linux ELF binary, and `vim`, because its 0.4.6 package installs no commands |

Verified guest shell behavior on 0.4.6:

- `exec` and `execFile` shells read no startup files. `sh -l`, `bash --login`, and `bash -l -i` all skip `/etc/profile` and `~/.profile`, so callers source `~/.profile` themselves.
- Setting `BASH_ENV` or `ENV` in `environment` breaks every shell with the error `not yet implemented: load config from $ENV/BASH_ENV`. The export keeps the base environment of agentos-core, except `PAGER`, which is `cat` because the guest has no `less`.
- `[ -r <missing file> ]`, `[ -x ... ]`, and `[ -w ... ]` return true in the guest, while `-f` and `-e` return false. Before `.profile` used `-f`, sourcing it printed `failed to source file` and returned 1 in every guest.
- Registry packages download on the host from `releases.rivet.dev`, so the guest needs no network for them. The default download timeout of 30 s fails on slow links, so the boot raises it to 5 minutes. A separate 60 s wait for package acquisition has no option in JavaScript, so a slow link can still fail the boot with `acquisition waiter exceeded 60000ms`. Run it again.
- The registry `jq` is jaq, and the registry `yq` is its own build. `yq --version` hangs for about 15 s, so the boot pipes a document through `yq '.a'` instead.

## Docker images

[architecture.md](architecture.md#docker-images-are-one-dockerfile-in-two-passes) explains how the Dockerfile builds them.

| Image | Modules | Use |
| --- | --- | --- |
| `ghcr.io/dayjobdoor/dotfiles:sandbox`, also tagged `latest`, `X.Y.Z`, and `X.Y` | `agent` | Agent sandbox and devcontainer. |
| `ghcr.io/dayjobdoor/dotfiles:desktop`, also tagged `X.Y.Z-desktop` and `X.Y-desktop` | `agent` and `desktop` | XFCE over RDP. `.devcontainer/compose.yaml` builds the same image locally and publishes it on `127.0.0.1:33389`. `mise run up` starts it. |
| `djd:full`, local only and not published | `agent` and `full` | The full toolbox. `mise run build full` builds it. `full-weekly.yaml` builds it weekly and runs `djd doctor` in it. |

Every image sets `DJD_NO_MUX=1` and puts the mise shims on `PATH`. The images that `mise run build` and `push.yaml` build also carry the commit in `DJD_REVISION`. Start the containers with `--init`, so that an init process reaps zombies. `compose.yaml` and `devcontainer.json` set it, and `mise run shell` passes it.
