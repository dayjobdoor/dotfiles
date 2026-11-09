# Changelog

What each release changed, newest first, in the style of [Keep a Changelog](https://keepachangelog.com). The versions are the GitHub releases, `X.Y.Z` tags that `tag.yaml` cuts after a green CI run on `main`; planned work is in [ROADMAP.md](ROADMAP.md).

## Unreleased

- OrbStack is no longer a VM target: the README recipe, the `orb` backend of `test:vm` and the OrbStack guard in `cloud-init/vm.yaml` are gone. Use Docker (OrbStack's Docker works on a Mac) or multipass; the VM tests run on incus and multipass.
- Docs: `references.md`, `tech.md` and `directory.md` replace `reference.md`; `requirements.md` and `problems.md` come out of `architecture.md`; `ROADMAP.md` and this file replace the planned-work section.
- Removed the i-have-adhd agent skill and its lock file; added `.env.example` with variable names only.

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
