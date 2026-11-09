# Requirements

What the repository has to deliver, what it does not, and how you tell that a machine or a change is done. [architecture.md](architecture.md) shows how it is built, [testing.md](testing.md) says which test proves which requirement, and [tech.md](tech.md) lists what each module declares.

## Scope

- Ubuntu 26.04 on amd64 and arm64. No macOS, WSL or other distribution is a target; a Mac appears only as the host of Docker, act and the VM tools.
- One command takes a fresh machine to a known state: `install.sh` (or `curl | sh`) installs mise, and `mise bootstrap` does the rest. The same repository builds the Docker image and the VM.
- Three targets drive it, smallest first: an agent sandbox (a disposable image or VM where coding agents run), a server (a VM that you reach over ssh or mDNS, with a firewall and docker), and a desktop (XFCE over RDP with Japanese input).

## What ships

| Piece | Must provide |
| --- | --- |
| Base, on every machine | zsh as the login shell, the core command-line tools, the dotfiles of `home/`, the zsh plugins and abbreviations, and the XFCE desktop over xrdp (TLS only, no root login) with PipeWire audio and Japanese input. The apps are ghostty, Brave, Zed and Zen (required), and Wireshark, Obsidian, Vicinae, Ferdium and fusuma. |
| `agent` module | The build tools, node, bun, python and uv, the coding agents pi and omp with their config, the `skills` CLI, and telemetry off. |
| `server` module | sshd with keys only, a firewall that denies inbound traffic except ssh and RDP from private networks, docker with published ports on `127.0.0.1`, and avahi. |
| `full` module | The personal toolbox; it implies `agent`. |
| `secrets` module | Environment secrets as age ciphertext, for machines you own. |
| Docker image | The base and `agent`, published to GHCR as `latest`, `X.Y` and `X.Y.Z`, with a shell or the desktop over RDP. |
| VM recipes | `cloud-init/vm.yaml` for multipass, OrbStack and incus: hostname `vm`, the user `dayjobdoor`, the install. |
| `djd` | `apply`, `update`, `status`, `doctor`, `module` and `secret`. |

## What does not ship

- A second configuration tool next to mise, and a migrations runner for imperative steps.
- A lockfile for the tools of a machine. Only the repository's own tools are locked; the image digest is the reproducible artifact.
- NLA for RDP, and a restriction of the RDP clipboard, drive and audio channels. [problems.md](problems.md#rdp-security-and-known-limits) lists them.
- Removal of apt packages by `djd module remove`; the packages stay.
- A committed password, token, account ID or key. [SECURITY.md](../SECURITY.md) is binding.
- Branch protection, rulesets and the other repository settings; [guidance.md](guidance.md#harden-the-repository-settings) lists them as steps.

## What done looks like

- On a machine, `djd doctor` exits 0 and prints an `ok` line for each of `ubuntu`, `mise-config`, `login-shell`, `bootstrap`, `dotfiles`, `plugins`, `xrdp-tls` and `xrdp-root-login`, plus `sshd` with the `server` module and `secrets` with the `secrets` module. `mise bootstrap plan --detailed-exitcode` reports no change.
- For a change, `mise run lint` and the narrowest test that covers it pass, and every Markdown mention of a changed name is updated ([AGENTS.md](../AGENTS.md)).
- For CI, the jobs `lint`, `image` and `vm` pass on amd64 and arm64.
- For a release, a green push run on `main` makes `tag.yaml` publish the next `X.Y.Z`, and `push.yaml` pushes images that pass `djd doctor` by digest before any floating tag moves ([maintenance.md](maintenance.md#release-chain)).
