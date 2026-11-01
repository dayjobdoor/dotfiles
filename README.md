# dotfiles

[![CI](https://github.com/dayjobdoor/dotfiles/actions/workflows/ci.yaml/badge.svg)](https://github.com/dayjobdoor/dotfiles/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Ubuntu 26.04](https://img.shields.io/badge/Ubuntu-26.04-E95420?logo=ubuntu&logoColor=white)
[![mise](https://img.shields.io/badge/managed%20by-mise-6f42c1)](https://mise.jdx.dev)

Ubuntu 26.04 dotfiles for coding-agent sandboxes, servers and an XFCE desktop over RDP, managed entirely by [mise](https://mise.jdx.dev). One `mise bootstrap` installs apt packages, writes system files, configures the firewall, links dotfiles, sets the login shell and installs tools. `djd` is a small CLI on top.

- **One tool.** No chezmoi, Ansible or Stow. The repo is the global mise config, and every machine role is a mise config environment.
- **Modules, not forks.** `agent`, `server`, `desktop`, `full` and `secrets` add up per machine and come off again with `djd module remove`.
- **Tested end to end.** CI builds the images on amd64 and arm64, logs in over RDP, installs the server and desktop modules into a fresh incus system container, and boots the portable subset in [Rivet agentOS](https://rivet.dev/docs/agent-os).
- **Public by design.** Secrets are committed only as age ciphertext, workflows are audited by jactionlint and pinned to commits, and gitleaks scans the history in CI and the staged changes in an opt-in pre-commit hook.

## Install

On Ubuntu 26.04 (amd64 or arm64), as a user with sudo:

```sh
curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | sh -s -- agent
```

What it changes on the machine:

- `TZ` defaults to Asia/Tokyo in `~/.profile`. Override it in `~/.config/djd/profile.local`.
- zsh becomes the login shell, and the `server` module adds your user to the `docker` group. Both need a new login.
- A real file that a dotfile would replace is moved to `<file>.djd-backup-<time>`.
- A login zsh on a real terminal starts herdr. Export `DJD_NO_MUX=1` (for example in `~/.config/djd/profile.local`) to skip it.
- The `server` module's firewall denies every inbound port except SSH (rate-limited) and RDP from private networks.
- The `desktop` module sets the system locale to ja_JP.UTF-8.
- The cloud-init files set the timezone to Asia/Tokyo, and `cloud-init/multipass.yaml` also sets a Japanese keyboard layout (`layout: jp`, `ctrl:nocaps`).

Unauthenticated GitHub API limits can stop tool installs. mise reads `MISE_GITHUB_TOKEN`, so set it in the environment of the `sh` that runs the installer. A `docker compose` build reads `GITHUB_TOKEN` from the environment instead. The token needs no scope, and [SECURITY.md](SECURITY.md#github-tokens) says why a scoped one is a risk.

```sh
curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | MISE_GITHUB_TOKEN=<token> sh -s -- agent
```

From a checkout, run `./install.sh agent server`. `make init ARGS="agent server"` does the same but needs make, which a fresh Ubuntu cloud image may not include (`sudo apt-get install make` first). Without module arguments it re-applies the current selection, which on a fresh machine is the base config. To install your own fork, see [Fork](#fork).

Or skip installing and use an image:

```sh
docker run --rm -it --init ghcr.io/dayjobdoor/dotfiles:sandbox
```

## Modules

| Module | Adds |
| --- | --- |
| base | zsh, git, make, core CLI tools (ripgrep, fd, jq, gh, lazygit, jj, starship, herdr, …), dotfiles |
| `agent` | node, bun, python, uv, pi, omp, skills, build tools, the global AGENTS.md of pi and omp, telemetry off |
| `server` | openssh-server (keys only), avahi, ufw firewall (RDP from private networks only), docker (published ports on `127.0.0.1` by default); see [SECURITY.md](SECURITY.md#server-module) |
| `desktop` | XFCE over xrdp with audio redirection (PipeWire), Japanese input (fcitx5-mozc), Noto CJK and HackGen NF fonts, ghostty, system locale ja_JP.UTF-8 |
| `full` | the whole personal toolbox (~180 tools; more than 10 GB of disk); implies `agent`. Its GUI packages install only together with `desktop` |
| `secrets` | your age-encrypted environment secrets; only for machines you own |

## djd

```sh
djd                       # list commands; djd module --help and djd secret --help show their arguments
djd apply                 # converge this machine to the repo
djd update                # pull, update mise, upgrade packages and tools
djd status                # checkout, modules, bootstrap state
djd doctor                # health check, exit 1 on failure
djd module list
djd module add desktop
djd module remove desktop # packages stay installed
djd secret keygen         # age key at ~/.config/djd/age.txt
djd secret set NAME       # prompt, encrypt into the secrets module
```

Machine-local settings (extra environment, shell additions, git identity) live in files outside the repo; [SECURITY.md](SECURITY.md#local-overrides) lists them.

`djd secret set` writes into the checkout (`mise-config/config.secrets.toml`), so storing secrets needs a checkout of your own fork. Run `djd secret keygen` once and `djd secret set GITHUB_TOKEN` for each value. Commit and push `mise-config/config.secrets.toml` (ciphertext only), run `djd update` on every other machine, copy `~/.config/djd/age.txt` to every machine you own, then `djd module add secrets` there. [docs/architecture.md](docs/architecture.md#secrets-use-the-age-support-of-mise) explains the design.

## Desktop over RDP

```sh
cp .devcontainer/.env.example .devcontainer/.env   # set PASSWORD
mise run up
```

`make up` and `mise run up` are the same task and need the checkout trusted by mise (`mise trust`, once per clone). Without mise, run `docker compose -f .devcontainer/compose.yaml up -d --build desktop`. `mise run down` stops the container. A devcontainer mounts the whole checkout, so keep only the RDP password (and the optional tunnel token) in `.devcontainer/.env`, never GitHub or other tokens.

Connect an RDP client (e.g. Windows App) to `localhost:33389` as `ubuntu`. The port is bound to `127.0.0.1` only.

## VMs and system containers

Both recipes read files from `cloud-init/`, so run them from a clone of this repository.

incus runs a system container with systemd on Linux. `security.nesting` lets the server module run Docker in it. The first three commands set incus up once on Ubuntu 26.04, and the group change needs a new login:

```sh
sudo apt install incus-base incus-client   # once
sudo incus admin init --minimal            # once
sudo adduser "$USER" incus-admin           # once, then log in again
incus launch images:ubuntu/26.04/cloud djd -c security.nesting=true -c cloud-init.user-data="$(cat cloud-init/vm.yaml)"
incus exec djd -- cloud-init status --wait
incus exec djd -- sudo -iu ubuntu sh -c 'curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | sh -s -- server desktop'
incus exec djd -- passwd ubuntu   # RDP login needs a password
incus list djd                    # connect an RDP client to this address, port 3389
```

The server module opens RDP only to loopback and private networks, and the incus bridge is private.

If the host runs ufw or Docker, which the `server` module sets up, the container gets no network until the host allows the bridge. The [Incus firewall guide](https://linuxcontainers.org/incus/docs/main/howto/network_bridge_firewalld/) lists the rules. For ufw they are `sudo ufw allow in on incusbr0`, `sudo ufw route allow in on incusbr0`, and `sudo ufw route allow out on incusbr0`. For Docker they are two `iptables -I DOCKER-USER` rules, the ones in `.github/workflows/ci.yaml`, which you have to make persistent across reboots yourself.

multipass ([install it](https://documentation.ubuntu.com/multipass/latest/how-to-guides/install-multipass/) on macOS, Windows or Linux) installs `server desktop` at first boot and imports the `gh:dayjobdoor` SSH keys. In a fork, see [Fork](#fork) first:

```sh
multipass launch 26.04 --name djd --cpus 4 --memory 8G --disk 40G --timeout 3600 --cloud-init cloud-init/multipass.yaml   # waits for the install
multipass exec djd -- sudo passwd ubuntu   # RDP login needs a password
multipass info djd                         # connect an RDP client to this address, port 3389
```

The default multipass size (1 CPU, 1 GB RAM, 5 GB disk) is too small for the desktop module. [docs/how-to.md](docs/how-to.md#try-it-in-an-orbstack-machine) covers OrbStack.

## agentOS

The portable subset (`.profile`, git config, WASM registry tools) runs in a [Rivet agentOS](https://rivet.dev/docs/agent-os) VM:

```sh
mise run agentos:export   # writes dist/agentos/bundle.json
mise run agentos:boot     # boots a VM with it and checks the shell, git config and tools
```

## Remove

Run these in order. The first needs `djd`, which the second deletes. This exact sequence ran in the sandbox image with only `agent` selected.

```sh
djd module remove agent server desktop   # every module `djd module list` shows as selected
mise dot unapply --group home --yes      # the base dotfile links
sudo chsh -s /bin/bash "$USER"           # login shell back to bash
cp --update=none /etc/skel/.bashrc /etc/skel/.profile ~   # djd apply deleted the defaults these links replaced
rm ~/.config/mise                        # the link to this repository's mise config
rm -rf ~/.dotfiles                       # a clone; if it is a link to your own checkout, use `rm ~/.dotfiles` instead
```

`~/.local/share/mise` and `~/.local/bin/mise` hold mise and the installed tools. Packages, ufw rules and the `docker` group stay; remove them with `apt`, `ufw` and `gpasswd -d "$USER" docker`. Files moved aside as `*.djd-backup-*` are yours to move back.

## Fork

Replace `dayjobdoor` with your GitHub user (`git grep -l dayjobdoor` lists the files). These places matter.

- `DJD_REPO` in `install.sh`. A fork's raw `install.sh` still clones the original repository unless this changes. The variable can also be set in the environment for one run.
- `REGISTRY_IMAGE` in `.github/workflows/push.yaml`, in lowercase.
- `ssh_import_id` and the install URL in `runcmd` in `cloud-init/multipass.yaml`.
- The `origin` URL and the dry-run `full_name` that `mise-tasks/ci` sets for act.

## Development

```sh
git config core.hooksPath .githooks   # gitleaks on every commit
mise trust                            # once per clone, by you on a machine you accept it on (AGENTS.md bans it elsewhere)
make                                  # list tasks
make lint                             # shell, mise configs, workflows + Dockerfile, DESIGN.md, docs links and secrets, in parallel (make lint:shell, lint:docs ... run one)
make lint:fix                         # rewrite shell and mise TOML formatting
make test                             # sandbox image: doctor, PATH, shell startup, backup and checkout re-apply, secrets round trip
make test:desktop                     # desktop image: RDP login starts XFCE through ~/.xsession, xrdp-sink is the default audio sink
make test:vm                          # fresh incus or multipass VM (OrbStack also works): server + desktop install, hardening, module removal
make ci                               # every CI job act can run: lint, sandbox, desktop, agentos (ARGS=sandbox for one)
make ci ARGS=--dry-run                # plan every job of every workflow, release ones included
```

`make <task>` is `mise run <task>`, except `make init` (runs `install.sh`) and `make apply|update|status|doctor|module|secret` (run `djd`). Repo tools are pinned in `mise.lock`, and [docs/how-to.md](docs/how-to.md#update-the-pinned-tools) says how to update them. Every test that installs or applies anything runs in Docker or a throwaway VM, never on your machine. Only `make lint` and `mise run agentos:boot` run host tools. [docs/ci.md](docs/ci.md) says what each CI job proves, and [AGENTS.md](AGENTS.md) has the rules.

## Issues and questions

Open an issue at [github.com/dayjobdoor/dotfiles/issues](https://github.com/dayjobdoor/dotfiles/issues). Report vulnerabilities as described in [SECURITY.md](SECURITY.md#reporting-a-vulnerability).

## License

[MIT](LICENSE)
