# Architecture

This page explains why the repository works the way it does. [reference.md](reference.md) holds the lookup tables, [maintenance.md](maintenance.md) describes the workflows and [testing.md](testing.md) the tests, and [guidance.md](guidance.md) has the task guides.

These dotfiles bring an Ubuntu 26.04 machine on amd64 or arm64 to a known state. `mise bootstrap` does all of the work: system packages, system files, the firewall, dotfiles, the login shell, and tools. The repository is the global mise config, and `djd` is a thin command-line tool over mise tasks.

Three targets drive the design, smallest first.

1. The agent sandbox is a disposable Docker image or VM where coding agents run. The `agent` module on top of the base builds it.
2. The server is a VM that you reach over ssh or mDNS, with ufw and docker. The `server` module builds it.
3. The desktop is XFCE over xrdp with Japanese input, in every VM and in the Docker image. It is part of the base, not a module.

## The checkout is the global mise config

`install.sh` links `~/.config/mise` to the `mise-config/` directory of the checkout, so mise reads the repository as its global config. The directory has that name because both `mise/` and `.config/mise/` would make mise treat the checkout itself as a project config.

## Dotfiles are one symlink per file

This repository links dotfiles through the `symlink-each` mode of mise. Every file becomes its own link, such as `~/.config/git/config` pointing to `~/.dotfiles/home/.config/git/config`, and every directory stays real.

Editing a deployed file edits the checkout. Programs that write next to their config, such as fcitx5, write into `~` and never into the repository. A symlink to a whole directory would let them write into the repository.

A program can still change a tracked file through its link. lazygit rewrites its config in place when it migrates renamed keys, and `git config --global` appends to `~/.config/git/config`. Both leave the checkout dirty. A program that saves through a temporary file and a rename, such as `sed -i`, replaces the link with a regular file. `mise dot status` then reports `exists but is not a symlink`, and `djd doctor` fails. `djd apply` moves the new file aside as `*.djd-backup-*` and links the repository file again. [How to keep an edit that a program made](guidance.md#keep-an-edit-that-a-program-made) shows how to save the edit first.

`~/.dotfiles` can itself be a symlink to a checkout elsewhere, because `install.sh` creates it. Moving the checkout then means relinking one path. The links stay absolute, which is the mise default, because `~` never moves on these machines.

## One install path covers three situations

`install.sh` runs the same steps whether you start from a checkout, from `curl | sh`, or inside the Docker build. The three differ in how `~/.dotfiles` comes to exist.

- From a checkout, `install.sh` makes `~/.dotfiles` a symlink to that checkout, but only when `~/.dotfiles` does not exist yet (a link that points nowhere counts as missing). When `~/.dotfiles` exists, `install.sh` says so and applies that tree, not the checkout it runs from.
- From `curl | sh`, it clones into `~/.dotfiles`.
- In the Docker build, the image first copies `install.sh`, the `djd` wrapper and `mise-config/` to `~/.dotfiles`, and it copies the full tree before its last pass.

```mermaid
flowchart LR
    A[install.sh] --> B[link ~/.dotfiles and ~/.config/mise]
    B --> C[install mise if missing or older<br>release from min_version]
    C --> D{modules given?}
    D -- yes --> E[djd module add]
    D -- no --> F[djd apply]
    E --> F
    F --> H[mise bootstrap]
```

The mise release has one source, the `min_version` line of `mise-config/config.toml`. `install.sh` reads it after it has linked or cloned the checkout. It installs mise when mise is missing or older than `min_version`, and it checks the installed version again afterwards. `MISE_VERSION` overrides the release to install, but `install.sh` refuses a value older than `min_version`. `lint:config` requires that `.mise/config.toml` and every `jdx/mise-action` pin in the workflows name the same release. `install.sh` ends by running the `djd` wrapper, which owns `PATH`, the locale, and `MISE_ENV`, so a curl install and a later `djd apply` run in the same environment. [reference.md](reference.md#bootstrap-phases-and-hooks) lists what `mise bootstrap` does, in order.

`install.sh` clones and links by hand, although `mise bootstrap --from <url> --from-dir ~/.dotfiles --config-dir mise-config` does the same two steps. The repository does not use that command for two reasons. It bootstraps before `djd module add` has written the module selection. And a checkout that you use in place needs a symlink, not a clone.

## A module is a mise config environment

Each module is a mise config environment, the file `mise-config/config.<module>.toml` ([reference.md](reference.md#modules) lists what each declares). The selection goes to `miserc.local.toml`, which git ignores, in one canonical order, so later modules win key collisions. The only dotfile group is `home`, which holds the pi and omp config as well, so it is always linked; only the `agent` module points the tools at it.

The `server` module owns the sshd hardening. Its `pre-dotfiles` hook fails an apply unless the drop-in `10-djd.conf` is in effect. The check lives in `hooks/sshd-keys-only`, which `djd doctor` runs too. It reads the setting without sudo from the `sshd_config` layout of Ubuntu and falls back to `sudo sshd -T`. After the drop-in changes, `server-pre-dotfiles` (not `sshd-keys-only`) reloads a running sshd once. The check fails with a message when `/etc/ssh/sshd_config.d` does not exist. It also falls back to `sudo sshd -T` when a drop-in contains an `Include` or cannot be read by the user, because the greps cannot see those settings. On 26.04, sshd is socket-activated. `ssh.socket` stays active, and `ssh.service` stays idle until a connection arrives. [SECURITY.md](../SECURITY.md#server-module) lists the rest of the hardening.

sshd keeps the first value it reads, but a `Match` block overrides a global value for the users it matches. When any `Match` line exists in `sshd_config` or `sshd_config.d`, the hook therefore always takes the slow path and runs `sudo sshd -T -C user=<current user>,host=localhost,addr=203.0.113.1`. That catches `Match all` and `Match User <current user>`. It does not see a `Match` for another user or for an address, and it does not see a `Match` in a file outside those two paths. The check covers the current user's effective settings, not every possible login.

`/etc/locale.conf`, the Docker image and the `djd` wrapper all use `LANG=C.UTF-8`, so tool output stays English for agents, ssh logins included. Only the RDP desktop session is Japanese: `~/.xsession` exports `LANG=ja_JP.UTF-8` before it starts XFCE. A selection from your own `MISE_ENV` would replace the module selection, which is why the `djd` wrapper unsets it. [reference.md](reference.md#modules) describes the case of a project that uses mise environments itself.

## The desktop is part of the base

There used to be a `desktop` module and a headless sandbox image next to a desktop image. The two differed in the XFCE and xrdp packages, a few apps, and one dotfile group, so the repository kept two images and two test paths for a small gap. Now the base config holds the desktop, every machine and the one Docker image get it, and a module is a machine role: `agent`, `server`, `full` or `secrets`.

What that costs, so it is a decision and not an accident: the image is about 2.6 times the size of the old sandbox (6.4 GB against 2.5 GB, measured on arm64), a headless server installs XFCE it never shows, and xrdp listens on 3389 on every machine. Only the `server` module adds the firewall rules that limit RDP to loopback and private networks, and `djd module add` warns when it is not selected. In a container the port is published by docker, and `compose.yaml` binds it to `127.0.0.1`.

GUI packages of `full` carry no `env` gating any more, and its `[tools]` never had one.

## Hooks live in the module that needs them

mise runs the hooks of every selected module in order, base first, so two modules that declare the same hook both run it. [reference.md](reference.md#bootstrap-phases-and-hooks) holds the one table of parts and hooks. This section gives the reasons.

- Base declares `pre-user`. It switches the login shell through sudo, because the plain `chsh` that mise runs asks for a password that cloud users lack.
- Base and `server` each declare `pre-dotfiles`. The base runs `hooks/dotfile-conflicts` for its dotfile group. It moves a real file that a dotfile would replace aside, because symlink entries refuse real files. It is a hook and not part of `djd apply`: mise runs the hooks of a part only when that part runs, so `--dry-run`, `--skip dotfiles`, and a bootstrap that stops earlier leave your files alone. The hooks of all selected modules run in order, base first, so a failing `server` hook still comes after the base hooks have moved files.
- The `server` module declares `post-packages`, which runs `hooks/server-post-packages`: it refuses the apply while sshd is still as it was, and only after its checks pass (also on the `DJD_SKIP_SSH_CHECKS` path, which skips the refusals) does it add the user to the `docker` group. sshd is socket-activated, so the drop-in that the files part writes next turns passwords and root login off from the next connection, whether or not the rest of the apply succeeds. A root apply, a user with no authorized key, or an sshd on another port than the firewall's 22 would be locked out, so those three stop the apply first, in that order. Its `pre-dotfiles` hook runs `hooks/server-pre-dotfiles` after the files part wrote the sshd drop-in, because the drop-in must exist before the check.
- The base declares `final`, which runs `hooks/desktop-final`. It purges the screen lockers and sets the xrdp security values after the packages exist. It makes no download. HackGen NF is the `http:hackgen` tool, which mise downloads and checks against a pinned checksum.

mise has native `[bootstrap.users]` and `[bootstrap.groups]` tables, and a plan with them added the user to the `docker` group. They need a fixed user name, and OrbStack runs as the host user, so the hook stays.

## Removal uses mise, and tools track latest

The repository has no migrations framework. Machine tools have no lockfile. Only the dev tools of the repository are locked, in `.mise/mise.lock`.

Removing things uses mise itself: `mode = "absent"` entries, `mise bootstrap --prune-dotfiles`, and `djd module remove`. That command runs `mise bootstrap unapply` and then `mise dot unapply --group`, because the first skips dotfile groups. apt packages stay installed.

Tools track `latest` behind `minimum_release_age = "3d"`, so a release must be three days old before mise installs it. `pi` and `omp` are the exception ([reference.md](reference.md#modules) gives the setting and the reason). The Docker image digest is the reproducible artifact. Bit-for-bit matching of the machines and a runner for imperative steps are open ([planned work](#planned-work)).

## djd forces the C.UTF-8 locale

`home/.local/bin/djd` runs `mise run djd:<cmd>` from `$HOME` with tool auto-install off. The djd tasks are plain bash, and installing tools belongs to `djd apply`. Running from `$HOME` keeps a `.mise/config.toml` in the current directory out of `mise bootstrap`.

The wrapper forces `LC_ALL=C.UTF-8`, and `install.sh` gets the same value because it ends by running the wrapper. With the mise release that `min_version` names, a Japanese locale breaks the firewall check, because mise decides that ufw is active by matching the English line `Status: active`. Under a Japanese locale, `mise bootstrap` then reports firewall drift forever. The desktop session sets such a locale, and orb and ssh forward `LC_ALL`, which sudo keeps. On those machines, run raw `mise bootstrap` commands with `LC_ALL=C.UTF-8` until mise pins the locale itself.

`djd module` and `djd secret` declare their arguments as usage specs with `#USAGE`. Mise therefore rejects a bad action or module name before the script runs, and `djd module --help` and `djd secret --help` print the arguments. `djd apply`, `djd update` and `djd status` pass extra flags through to the mise command they run; `djd doctor` ignores them. `mise run lint` validates the specs with `mise-config` as the global config.

## Secrets use the age support of mise

mise has four secret features, and this repository uses one of them.

| mise feature | Fits here? |
| --- | --- |
| `[dotfiles]` `encrypt = true` | No. It works only with `mode = "track"`, which uses the history repository of mise. This repository deploys with symlinks. |
| `[dotfiles]` `mode = "fnox"` | No. [fnox](https://fnox.jdx.dev) is a separate tool. It keeps the encrypted file in its own global config on each machine, and `mise dot apply` writes the file into place. Nothing reaches the repository. |
| `[env]` age values, experimental | Yes. The `secrets` module uses it, and that module is the only one that sets `experimental = true`. |
| `[bootstrap.secrets]` | No. It supplies secret inputs to bootstrap templates from environment variables. |

The flow across two machines:

```mermaid
sequenceDiagram
    participant A as machine A (your fork)
    participant R as GitHub repo
    participant B as machine B
    A->>A: djd secret keygen (~/.config/djd/age.txt, mode 600)
    A->>A: djd secret set NAME (ciphertext into config.secrets.toml)
    A->>R: commit and push config.secrets.toml
    B->>R: djd update
    A-->>B: copy age.txt out of band
    B->>B: djd module add secrets
    B->>B: djd doctor (key present, mode, every value decrypts)
    B->>B: mise activate, mise exec, shims decrypt NAME
```

- `djd secret keygen` creates `~/.config/djd` with mode 700, writes the age identity with mode 600, and refuses to overwrite an existing key.
- `djd secret set NAME` prompts for a value and writes `NAME = { age = "..." }` into `mise-config/config.secrets.toml`. A name that exists is replaced in place. It passes `MISE_EXPERIMENTAL=1`, because mise marks age encryption experimental. Only ciphertext reaches the repository. An empty answer replaces an existing value with an empty one.
- The task is `raw=true`. Without it, mise stops feeding stdin to a task once the selected `secrets` module has values to redact. Every `djd secret set` after the first then stored an empty value and exited 0, and `djd doctor` still said ok, because an empty value decrypts. The image test sets two values in a row with the module selected and reads both back.
- `djd module add secrets` makes the values visible to interactive shells through `mise activate`, to `mise exec` and `mise run`, and to every tool that starts through a mise shim. A program that a shimmed tool starts inherits them. `sh -c`, `bash -lc`, and `zsh -lc` do not see them, so `curl -H "...$TOKEN"` from `zsh -lc` sends an empty secret.
- A decrypted value goes through the `$VAR` and `{{ }}` expansion of mise. A value stored as `pw$HOME-end` comes back with `$HOME` replaced, and an undefined `${USER}` prints a mise warning on every call. Do not store a secret that contains `$` or `{{`. The investigation found no mise setting that turns the expansion off.
- The key at `~/.config/djd/age.txt` is the only identity that decrypts. `djd secret set` encrypts to that key alone, so an SSH key is never a recipient.
- `age.strict = false` is deliberate. With strict on and the module selected, a machine without the key fails every mise command, including `djd secret keygen`, `djd doctor`, `djd module remove secrets`, and every shim, so the machine cannot recover itself. With strict off, a machine without the key keeps working with the values unset. That setting also hides a wrong or unreadable key, so `djd doctor` runs `mise env` with `MISE_AGE_STRICT=true`. It fails when the secrets module is selected and the key is missing, has a group or other permission bit (0600 and 0400 pass), or cannot decrypt a value.
- One key serves all your machines. Copy `age.txt` to each one and keep an offline backup, for example in a password manager. If you lose every copy, the values are unrecoverable. mise has no rekey command, so adding a recipient means entering each value again.

Files such as SSH keys and `rclone.conf` stay out of the repository. You have three options. Put a secret from the file in the secrets module, copy the file by hand, or store the file with `fnox set --file`. For the last option, declare the file with `mode = "fnox"` in a local config.

## Shells share one .profile, and caches keep them fast

`~/.profile` is the file that every login shell and every interactive shell reaches. It stays POSIX and starts no program. `sh -c` and a non-login `bash -c` do not read it. [reference.md](reference.md#shell-startup-files) lists which file each shell reads.

mise shims are on `PATH` from `.profile` and from `ENV PATH` in the images. Non-interactive agent shells such as `sh -c`, `bash -lc`, and `docker exec` therefore find every managed tool without `mise activate`. A shim costs about 50 ms per call, against 3 ms for the real binary. Interactive shells skip the shim, because `mise activate` puts the real tool directories first. Both numbers were measured once, in October 2026, on an arm64 Mac running OrbStack, and cannot be reproduced from this repository. The images also set `LANG=C.UTF-8`, because `docker run` and `docker exec` read no `~/.profile`. Without it, `tree` prints a Japanese file name as octal escapes in a plain `docker run` of the image.

The rc files cache the init script of each tool in `$XDG_CACHE_HOME/{zsh,bash}/init/` and write it atomically. `djd apply` clears the cache after bootstrap. Without the cache, an interactive zsh takes 1.39 s to start. With the cache, it takes 75 ms. Both numbers are hyperfine means of `zsh -i -c exit` in the image, measured once in October 2026 on an arm64 Mac running OrbStack.

One init stays uncached. `mise activate` embeds the current `PATH` in its output, so a cached copy would reset `PATH` for later shells.

The zsh plugins are named in `home/.config/sheldon/plugins.toml` and managed by sheldon, a mise tool. A default branch would put whatever it holds that day into shells that may see secrets, so every plugin is pinned to a commit with `rev`. To update one, set a newer `rev` and run `djd apply`. `hooks/sheldon-lock` runs `sheldon lock` after the tools, because sheldon has to be installed first, and the Dockerfile runs it after its dotfiles pass. Sheldon checks out submodules at the commit that a plugin pins, so zsh-abbr brings zsh-job-queue with it and needs no entry of its own; mise's `[bootstrap.repos]` clones no submodules, which is why the plugins moved. `.zshrc` runs `sheldon source` through the init cache, before `compinit`, and each plugin loads through zsh-defer. A first shell before the first apply has no sheldon and loads no plugin, and prints nothing. Plugin drift shows in `djd doctor`. The median of ten interactive starts with the old plugin set was 102.5 ms, measured once in November 2026 in the sandbox container with a method that differs from the hyperfine runs above; the new set has not been measured.

[SECURITY.md](../SECURITY.md#local-overrides) lists the machine-local overrides.

An alias is defined in exactly two places. A `[shell_alias]` entry of `config.toml` replaces a command: `mv`, `cp`, `rm`, `mkdir`, `ls`, `cat`, `ping` and `tree`. `[shell_alias]` works in bash, zsh, and fish, and `mise activate` sets the entries in each interactive shell, so no `command -v` guard is needed. A zsh-abbr abbreviation in `home/.config/zsh-abbr/user-abbreviations` is a shortcut that expands as you type, so the command line shows what runs: `l`, `ll`, `la`, `lt`, `lh`, `ggg`, `web`, `cx`, `cv` and `cb`. Abbreviations exist in zsh only. The old functions are gone: `ping` and `tree` became aliases, which cannot default the host to 1.1.1.1 and cannot skip the color when the output is a pipe, and `sec` became the script `home/.local/bin/sec`. A side effect is that bash now has `rm -i`, `cp -i` and `mv -i` too, which only zsh had before.

## Files follow XDG where the tool allows

`.profile` exports the four XDG variables with the defaults of the specification. The shell files keep history in `$XDG_STATE_HOME`, completion dumps and init scripts in `$XDG_CACHE_HOME`, and configuration in `$XDG_CONFIG_HOME`. Four files stay directly in `~`, because their programs read only that path: `.profile`, `.bash_profile`, `.bashrc`, and `.zshenv`. `.zshenv` then moves zsh to `ZDOTDIR`. The X session reads `~/.xsession`, which x11-common hard-codes.

The repository assumes the default locations. The dotfile deployment, the age key, and the git include path name `~/.config` directly. The `PATH` of the Dockerfile, the gh credential helper in the git config, and the `Exec` lines that the zed and zen `postinstall` scripts write name `~/.local/share/mise/shims` directly. Setting other XDG directories changes what shells and tools resolve themselves, and it would break those fixed paths.

Some programs still write into `~` or into their config directory, and the repository accepts that. Two reasons decide. A variable that `.profile` exports reaches login shells and not `docker exec`, so a tool would keep its state in two places. Some tools have no setting at all. npm and bun are the exception, because mise shims apply the `[env]` table of the `agent` module to every shell type, so those two follow XDG everywhere. gpg is not a mise tool, so it stays. [reference.md](reference.md#xdg-locations) lists what lands where.

## The desktop apps each carry a trust anchor

The desktop requires four apps. A failed install fails `mise bootstrap`, and `tests/desktop-apps.sh` checks each app in the image and in the VM test. The image test also starts Brave and Zen headless and opens a window for ghostty and Zed inside the RDP session. Wireshark, Obsidian, Vicinae, Ferdium and fusuma install as well. A failed install of any of them fails the apply too, so each is a pinned release with a checksum or an archive package, and `tests/desktop-apps.sh` only checks that it is on `PATH` with a menu entry. No app installs through `curl | sh`.

| App | Source | What proves the download |
| --- | --- | --- |
| ghostty | `apt:ghostty`, Ubuntu universe | The signed Ubuntu archive. |
| brave | `apt:brave-browser` from Brave's apt repository | The three signing-key fingerprints in `[bootstrap.apt.sources.brave-browser]`. mise keeps only those keys, and a changed key fails the apply. They match brave.com/signing-keys. |
| zed | mise `github:` tool | The asset digest, always, and the GitHub artifact attestation when the release has one. mise does not require one, so a release uploaded with a stolen maintainer token, which carries none, passes like Zen. |
| zen | mise `github:` tool | The asset digest that GitHub reports. Upstream publishes no signature and no attestation, so this shows that the download matches the release listing, not who built it. |

Brave's repository has no `resolute` suite, so the source sets `suites = "stable"`. Both `github:` tools track `latest` under the 3-day `minimum_release_age`, so mise skips the newest Zen release for three days. mise has no registry entry for either app, and a templated `asset_pattern` made `mise lock` record the aarch64 asset for linux-x64, so each tool names its asset per platform. Zed and Zen ship no menu entry that survives an upgrade. Each `postinstall` writes one with `Exec` on the mise shim and regenerates it on every install.

Brave aborts inside a container unless it runs with `--no-sandbox`, because Docker's default seccomp policy blocks namespace creation (tested on OrbStack in November 2026). The flag also switches off Brave's renderer seccomp-bpf sandbox. The Dockerfile adds it to a user-level copy of the menu entry, and the module does not, so a VM keeps Brave's sandbox. The image test starts Brave through that entry, and with the system entry instead Brave aborts with `Failed to move to new namespace`. A seccomp profile that allows user namespaces would keep Brave's sandbox on without `SYS_ADMIN`, but it applies only to containers started with it, so `docker run` of the published image would still abort. The repository ships none, and no one has run Brave under one. [SECURITY.md](../SECURITY.md#the-desktop) states the trade.

Zed and Zen each carry an in-app updater that would replace files in the mise install directory without mise's digest check and without the release age. `ZED_UPDATE_EXPLANATION` in the base `[env]` makes Zed skip its update poll, and the Zen `postinstall` writes `distribution/policies.json` with `DisableAppUpdate` and `DisableTelemetry`. A headless screenshot of Zen's `about:policies` listed both as active (November 2026). Updates go through `mise upgrade`. mise also puts a tool's own bin directories ahead of `PATH` while a `postinstall` runs, so both scripts reset `PATH` to `/usr/bin:/bin`, and `filter_bins` limits what each tool puts on `PATH`.

HackGen NF has no Ubuntu package and no GitHub asset digest, so it is the `http:hackgen` tool with a pinned version and SHA-256, and a wrong checksum fails the install with the expected and the actual value. Its `postinstall` resets `PATH` for the same reason and copies the fonts out of the install directory, because the next upgrade deletes the versioned directory ([reference.md](reference.md#files-that-modules-manage) has the details).

## The RDP service is TLS only and keeps the other xrdp defaults

The image and every machine set `security_layer=tls` and `AllowRootLogin=false`, and `djd doctor` and the image test check both. The values are the hardening that this repository chose. The rest of the xrdp defaults stay as the package ships them, and some are weak. [reference.md](reference.md#rdp-security-and-known-limits) lists the probe results and the open limits, and [SECURITY.md](../SECURITY.md#known-limits-of-the-rdp-service) summarizes them.

Two facts explain the settings, and the probe results are in the reference. `security_layer=hybrid` is not a valid value in this xrdp, so a typo or an upgrade to it silently re-enables the legacy RDP layer. And this xrdp has no NLA at all, so the choice is TLS or negotiate, not TLS or NLA.

## Docker images are one Dockerfile in two passes

`.devcontainer/Dockerfile` builds the image from `ubuntu:26.04`. The modules go in as `DJD_MODULES`: `agent` for the published image, and `agent full` for the `full-weekly.yaml` smoke build. The Dockerfile runs `install.sh` as `ubuntu` in two passes, and the first pass is two `RUN`s.

| `RUN` of `install.sh` | Sees | `DJD_BOOTSTRAP_FLAGS` | Token | Why |
| --- | --- | --- | --- | --- |
| First, pass one | `install.sh`, the `djd` wrapper, `mise-config/` | `--skip tools,dotfiles` | none | The maintainer scripts of apt packages, and the `apt-get purge` of the desktop final hook, run in the environment of the mise process, so they must not see the token. |
| Second, pass one | the same files | `--only tools` | BuildKit secret `github_token`, as `MISE_GITHUB_TOKEN` | Only tools reach GitHub. |
| Last, pass two, after `COPY . ~/.dotfiles` | the full tree | `--only dotfiles` | none | An edit to dotfiles, docs, or tests then reuses the slow layers from the build cache. |

The first `COPY` brings the `djd` wrapper along, because `install.sh` ends by running it.

The layers were measured with `docker history` in November 2026 (arm64): 2.7 GB for the packages and 3.4 GB for the tools. The tools layer was 4.7 GB until the same `RUN` started to delete `~/.cache/mise/downloads-cas`, the archives that mise keeps beside every unpacked tool, which took the image from 7.66 GB to 6.39 GB. On a machine the same store grows by 1.2 GB, so `config.toml` sets `cache_prune_age = "1d"` and `djd apply` runs `mise cache prune`. Dropping the Recommends of the apt packages (`APT::Install-Recommends "false"`) was tried and gives another 0.46 GB, but it removes 359 packages, among them the fcitx5 GTK and Qt frontends that Japanese input needs, `dbus-user-session`, the icon theme and the AT-SPI bridge, so the repository keeps the Recommends.

The image environment is `DEBIAN_FRONTEND=noninteractive`, `DJD_NO_MUX=1`, and `LANG=C.UTF-8`, then `PATH` with the mise shims, and `DJD_REVISION` last, so a new commit never invalidates the cached layers. `DJD_NO_MUX` stops `.zprofile` from starting herdr in every `docker run -it` shell. `LANG` is set because `docker run` and `docker exec` read no `~/.profile`. The desktop session sets `ja_JP.UTF-8` itself, in `~/.xsession`, and the image test asserts it ([testing.md](testing.md#the-desktop-in-the-image-on-amd64-and-arm64) describes it). [reference.md](reference.md#docker-images) lists the images.

## A container and a VM differ in three things only

The image and a VM install the same base, with the same user (`dayjobdoor`), the same hostname (`vm`; `compose.yaml` sets it for the container), the same locales and the same dotfiles. Three differences remain, and each has one cause.

- **No init in the container.** There is no systemd, so `djd-desktop-entrypoint` starts xrdp, `~/.xsession` starts PipeWire under its own supervisor, and nothing restarts a service. A VM has systemd units for all of that.
- **Sandboxes.** Docker's seccomp policy blocks namespace creation, so the Dockerfile adds `--no-sandbox` to the menu entries of Brave, Obsidian and Ferdium. A VM keeps their sandboxes; on a kernel with AppArmor, `/etc/apparmor.d/djd-electron` lets the two Electron apps use them.
- **The `server` module.** sshd, the firewall rules, docker and avahi need systemd and a real network, so only a VM selects `server`. In a container, docker publishes RDP on `127.0.0.1` and nothing else is open.

## CI mirrors local tasks, and releases are safe to repeat

Every CI job runs the mise task that you run locally, so a green CI run and a green `make` run mean the same thing. Each task declares the tools it needs, so a job installs only those. [testing.md](testing.md#jobs-in-ciyaml) lists the jobs.

Four decisions shape the workflows.

- A docs-only change skips `ci.yaml`, so it never releases, and `docs.yaml` runs the link and secret checks on it instead. [maintenance.md](maintenance.md#workflows) has the path filter and its exceptions.
- Releases only move forward and never repeat. `tag.yaml` tags a commit only when it contains the newest `X.Y.Z` tag, and only the newest release moves the floating tags, so a re-run of an older CI run cannot move `latest` backward. A re-run for a commit that already has a release publishes nothing, so a fixed tag is not rebuilt with today's `latest` tools. [maintenance.md](maintenance.md#release-chain) lists the rules.
- `tag.yaml` waits for the `push.yaml` run it dispatched and fails with it. A tag push by the `GITHUB_TOKEN` starts no workflow, and `push.yaml` runs as the bot, so nobody would be notified of a failed publish. The `tag.yaml` run belongs to the person whose push produced the release.
- Release builds use no build cache, so a published image cannot reuse a cache entry that another workflow wrote. `push.yaml` then smoke-tests each pushed image by digest with `djd doctor`, because the published bytes are rebuilt and can differ from the image that CI tested. A red smoke test stops the merge job, so no floating tag moves.

GitHub documents private as the default visibility of a new GHCR package. The first release of this repository came out public, and an anonymous `docker manifest inspect` resolved every tag. After the first release of a fork, check the visibility. [How to publish the first release](guidance.md#publish-the-first-release) shows how.

## Planned work

Nothing here is needed to use or change a machine.

- A global lock for mise tools, for machines that must match bit for bit: `lockfile = true` in the global config, then `mise lock --global`.
- A `migrations/` runner for changes that need imperative steps, in the style of Omarchy (omarchy.org, a Linux setup by DHH).
- Omarchy-style themes, which switch the colors of many programs at once. The plan renders the tokens of `DESIGN.md` into the ghostty, starship, XFCE, and fzf configs, so the Colors table no longer needs a manual sync.
- `djd menu`, a menu over the djd commands, built with gum (charmbracelet/gum, a tool for menus and prompts in shell scripts).
