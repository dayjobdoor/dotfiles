# Changelog

What each release changed, newest first, in the style of [Keep a Changelog](https://keepachangelog.com). The versions are the GitHub releases, `X.Y.Z` tags that `tag.yaml` cuts after a green CI run on `main`; planned work is in [ROADMAP.md](ROADMAP.md). `tag.yaml` cuts the next patch release after every green push run on `main`, so a change adds its entry under the next version, or under a new `Unreleased` heading until that release exists.

## 0.0.15 (2026-11-10)

- Shell: one `compinit` per shell (mise's hook no longer runs a second), completions of uv, omp and mise load after the prompt, the init cache keys on the command line and forks nothing, and plugins, fzf and atuin are skipped without a terminal (no more `can't change option: zle` for agents). A missing or stale sheldon lock no longer makes every shell try to clone.
- Compose: a healthcheck (xrdp listening), and `mise run up` waits for it, so an empty `PASSWORD` fails the command instead of crash-looping behind a success message.
- Dotfiles: `lazydocker/config.yml` is the name lazydocker reads (it was `config.yaml`), the `web` abbreviation opens a real site, `sec` rejects invalid names and no longer glues a line onto a file without a final newline, fusuma's four-finger swipes use XFCE's Ctrl+Alt+arrow shortcuts, and a few settings that did nothing are gone (ghostty, starship). pi no longer greps a `~/.aliases` that nothing creates, and omp's invalid `autoLearn` key is removed.
- Agents: omp's ponytail is the same npm release as pi's, and the pin rule in `docs/guidance.md` covers git pins. `lint:config` fails when pi's `AGENTS.md` and omp's `RULES.md` differ.
- `full`: entries that installed no tool are gone (pyright, pandas, hacs, bash-completion, cmatrix, four conda libraries, spotify-tui, a second ruby, libstd-rust-dev); 172 tools and 32 apt packages.
- Lint and tests: `lint:workflows` checks the dockerignore's credential patterns and validates `compose.yaml`, `lint:shell` takes any `sh` or `bash` shebang, `test:vm` stops when `cloud-init/vm.yaml` has no install marker, and cloud-init's install fails when the download does. The Docker build no longer reruns its last layers for a change in the docs.
- Docs: the `warp` module, hostnames, the base tool list, HackGen's single checksum, menu entries, tag release steps, wrong links and several counts match the code.

## 0.0.14 (2026-11-10)

- Compose: the RDP port is fixed at 3589 on 127.0.0.1 (`127.0.0.1:3589:3389`); `RDP_PORT` is gone, so a value in your `.devcontainer/.env` is ignored.
- Image build: the apt archives and `~/.cache/mise` are BuildKit cache mounts, so a rebuild of those layers downloads nothing again (the apt download alone took 104 to 270 s cold and 12 s warm); the image is the same. `docker builder prune` clears them.
- Module `warp`: Cloudflare WARP from Cloudflare's apt repository, for VMs and real hosts (`djd module add warp`; register with `warp-cli registration new`). The Docker image does not carry it, and `test:vm` installs it and checks that `warp-svc` is active.
- Image: `freerdp3-x11` (`xfreerdp3`) is in the base, and `git-lfs` with the `[filter "lfs"]` of `git/config`. The `full` module adds `vhs` and `fnox` (183 tools).
- Dotfiles: `cheat` (conf and 16 personal sheets), `gh/config.yml` (https) and `ripgrep/config`, which only the typed `rg` alias reads, so the rg of agents keeps its defaults.
- Shell: autojump and enhancd are sheldon plugins pinned to a commit, next to zoxide; fzf stays a mise tool.
- Docs: Brave keeps `--no-sandbox` in the container, and `problems.md` records why a seccomp profile that allows user namespaces was rejected (it killed the XFCE session).

## 0.0.13 (2026-11-10)

- Compose: the service is `ubuntu`, not `desktop`. Stop it with `docker compose -f .devcontainer/compose.yaml stop ubuntu`; `mise run up` and `mise run down` are unchanged.
- xrdp: `hooks/desktop-final` drops the generic `vnc-any` and `neutrinordp-any` sessions from `xrdp.ini`, and `test:desktop` asserts that none is left.
- Server: `hooks/sshd-keys-only` falls back to `sshd -T` when the `10-djd.conf` drop-in is missing, instead of passing on the stock layout.
- Shell: `chpwd` lists with `command ls`, and the `tree` alias no longer passes `-N`, so the control bytes of a file name are escaped; ghostty asks before a program writes the clipboard (`clipboard-write = ask`).
- Tests: `tests/tree.sh` leaves nested git repositories, worktrees and submodule entries out of the archive, and `tests/tree-check.sh` has a fixture for them.
- Agents: the pi extensions and the omp plugins are pinned to a version or commit, and the pi thinking level `middium` is `medium`. `docs/guidance.md` says how to bump a pin.
- Mise: the npm lock graph lives in `.mise/locks/` only (the copy nested one `.mise/` level deeper is gone), and `cheat` comes from the aqua backend, which ships linux/arm64.
- Docs: claims that had drifted from the code are fixed (push smoke test, `postinstall` scripts, locale, `djd` commands, directory layout), and `djd doctor` points at `mise dot add` for keeping an edit that a program made.

## 0.0.12 (2026-11-10)

- OrbStack is no longer a VM target: the README recipe, the `orb` backend of `test:vm` and the OrbStack guard in `cloud-init/vm.yaml` are gone. Use Docker (OrbStack's Docker works on a Mac) or multipass; the VM tests run on incus and multipass.
- Docs: `references.md`, `tech.md` and `directory.md` replace `reference.md`; `requirements.md` and `problems.md` come out of `architecture.md`; `ROADMAP.md` and this file replace the planned-work section.
- Removed the i-have-adhd agent skill and its lock file; added `.env.example`, which lists variable names and no secret values.

## 0.0.11 (2026-11-09)

- Image: the mise download store is deleted in the tools layer, 7.66 GB down to 6.39 GB. On a machine `cache_prune_age` is one day and `djd apply` runs `mise cache prune`.
- CI: timeouts follow the measured run times.
- Docs: `how-to.md` is `guidance.md`; `ci.md` is split into `maintenance.md` and `testing.md`; the tools, apps and actions are listed with their repositories.

## 0.0.10 (2026-11-09)

- Dependencies: `jdx/mise-action` 5.2.4 to 5.2.6.

## 0.0.9 (2026-11-09)

- One desktop environment: the `desktop` module and `config.desktop.toml` are gone, the desktop is part of the base, and there is one image, `djd:latest`.
- Added Wireshark, Obsidian, Vicinae, Ferdium and fusuma, and the Japanese input and keyboard settings.
- zsh plugins come from sheldon at pinned revisions (zsh-abbr with zsh-job-queue); aliases that replace a command are mise `[shell_alias]`, shortcuts are zsh-abbr abbreviations, and `.functions` is gone. `djd doctor` checks the plugin lock.
- pi and omp configs moved into `home/.config`; `herdr-dev` is the herdr autostart.
- `cloud-init/vm.yaml` replaces the per-tool files, with hostname `vm` and the user `dayjobdoor`; the Docker image uses the same user and hostname.
- The repository's own mise config, lock and tasks moved into `.mise/`.

## 0.0.8 (2026-11-08)

- `djd` and hooks: a refused apply grants nothing, `djd update` survives a branch without an upstream, and the shell init cache is keyed by its arguments.
- `install.sh`, make and CI verify the mise release and stop parsing `ARGS` as shell; the entrypoint rejects passwords with a newline.
- Tests and workflows: assertions that can fail, and cleanup on every exit.
- Removed the agentOS export and what served it.

## 0.0.7 (2026-11-06)

- The server module refuses an apply that would lock the user out of ssh, and warns when its hardening is removed.
- xrdp restarts once per change, the RDP password reaches the entrypoint as a secret, and apt maintainer scripts no longer see the GitHub token.
- Working ghostty shell integration, init cache keyed by the installed binary, quieter login shells.
- `tag.yaml` queues only real releases, and `push.yaml` publishes only commits on `main`.

## 0.0.6 (2026-11-02)

- Pinned zsh plugins, a single mise pin, an offline lock, hardened workflows.
- A per-container xrdp TLS key, audio cleanup at logout, and a supervised wireplumber.
- `djd doctor` checks what the hooks enforce; conflicts move aside only when dotfiles apply.

## 0.0.5 (2026-11-01)

- xrdp is TLS-only and refuses root logins; Zed telemetry and auto-update are off.
- The four desktop apps (ghostty, Brave, Zed, Zen) are required, each with its trust anchor, and tested in the image and the VM.
- PipeWire audio over RDP, and `test:desktop` launches the apps inside an RDP session.

## 0.0.4 (2026-10-31)

- `test:vm` runs on incus and multipass, with OrbStack as a third backend.
- `djd doctor` fails when the secrets module cannot decrypt.

## 0.0.3 (2026-10-31)

- Release notes list the commits and the image pull commands.

## 0.0.2 (2026-10-31)

- npm and bun follow XDG through the agent module's mise env.

## 0.0.1 (2026-10-31)

- First release: Ubuntu 26.04 dotfiles managed entirely by mise.
