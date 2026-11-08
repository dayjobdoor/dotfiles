# History and comparison

This page tells where the repository came from and why it differs from its source. You do not need it to use or change a machine. [architecture.md](architecture.md) explains the design.

## Compared with budybye/dotfiles

The table comes from the workflows and the run history of budybye/dotfiles, read with `gh run list -R budybye/dotfiles` in October 2026. Every CI job here also runs locally. `mise run ci <job>` runs it with act, and `make test:vm` runs the VM test with incus, multipass, or OrbStack.

| budybye/dotfiles | This repository | Why |
| --- | --- | --- |
| `test.yaml` runs `make init` on the runners and swallows tool failures with `\|\| echo "mise install failed."`. Runs stayed green although `pipx:marimo`, taskctl, and vegeta failed to install. | `test` and `vm` fail when any package, tool, or hook fails. | A green run has to mean that the machine converged. |
| The `lxd` and `rpi` jobs launch `ubuntu:26.04` in LXD with cloud-init and print OS information. | The `vm` job runs the full server and desktop install in that container and checks the result. | The LXD job was the only systemd coverage, and it asserted nothing about the result. |
| A "clean space" step frees runner disk before the install. | None. | Its own log shows 88 GB free before the cleanup on a 145 GB disk in October 2026, enough for the images that CI builds. The weekly `full` build died once with `No space left on device`, and `full-weekly.yaml` now prints `df -h /` first. |
| The daily schedule in `push.yaml` rebuilds the images to warm the BuildKit cache. | CI runs weekly, and releases build without a cache. | The weekly run detects drift without spending runner hours on a cache. A build without a cache gives cache poisoning no path into a published image. |
| `build-dev` publishes a separate devcontainer image. | None. | The devcontainer builds the same Dockerfile as the sandbox image. |
| The merge step tags `X.Y.Z`, `X.Y`, the flavor names, and `latest`. | The same scheme. | The scheme works, so it stayed. |
| The build argument `DOTFILES_REV` is checked against the cloned commit. | The build argument `DJD_REVISION` is shown by `djd status`. | The build copies the checkout, so there is nothing to compare. |
| `ipfs.yaml` pins a mirror clone to IPFS through Filebase. | Not ported. | GitHub and GHCR are enough for distribution. |
| Jobs for macOS, Windows, and WSL. | None. | This repository targets Ubuntu only. |

## Origin

This repository started in 2026 as a partial copy of the chezmoi-based [budybye/dotfiles](https://github.com/budybye/dotfiles). It was rebuilt around mise before its first public commit.

The copy had these problems:

- It had real shell files beside many empty placeholder directories. Its `mise.toml` had one task, which echoed `dotfile`. Its `install.sh` installed mise and applied nothing.
- Its Docker images and CI cloned budybye/dotfiles and ran a `make init` that did not exist here. Its devcontainer was a privileged docker-in-docker setup.
- It held files that are unsafe in a public repository: an unignored local `.env`, and cloud-init files with plaintext passwords. Neither was ever committed.
- Its shell init ran twice per login, because `.zprofile` sourced `.zshrc`. `.profile` had side effects and forced `TERM` and `LC_ALL`. `.bashrc` had a RHEL path. Some aliases changed the meaning of `grep`, `find`, and `cd`.

This repository carried these parts over from budybye/dotfiles:

- The zsh setup.
- The git config, without the repo-level `[core]` keys, the machine ID, the per-directory identities, the `git-lfs` filter, and the forced tag signing. `git lfs install` adds the filter where git-lfs exists. Tag signing belongs in `user.conf` next to a key.
- starship, herdr, and a trimmed plugin list (taken from budybye's sheldon file; here the plugins are pinned `[bootstrap.repos]` entries and sheldon is not used).
- ghostty, without the macOS keys.
- The tool list, as the module `full`, and the apt list.
- The structure of the release workflow.
- The `make init` entry point, and the key handling of `make age-keygen` that refuses to overwrite a key. That handling is now `djd secret keygen`.
- The design tokens of `DESIGN.md`.
- The lessons in its problem notes: no screen lockers and no im-config under xrdp.

It dropped these parts:

- chezmoi, and the Makefile-driven setup. The Makefile now runs mise tasks, with `djd` and `install.sh` behind the machine targets.
- Passphrase-encrypted files.
- The Windows and WSL CI jobs.
- The dev image, IPFS pinning, and the daily cache-warming build.
- The cloud-init files with passwords.
- Support for macOS.

## Planned work

- A global lock for mise tools, for machines that must match bit for bit: `lockfile = true` in the global config, then `mise lock --global`.
- A `migrations/` runner for changes that need imperative steps, in the style of Omarchy (omarchy.org, a Linux setup by DHH).
- Omarchy-style themes, which switch the colors of many programs at once. The plan renders the tokens of `DESIGN.md` into the ghostty, starship, XFCE, and fzf configs, so the Colors table no longer needs a manual sync.
- `djd menu`, a menu over the djd commands, built with gum (charmbracelet/gum, a tool for menus and prompts in shell scripts).
