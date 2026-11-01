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
- A real file that a dotfile would replace is moved to `<file>.djd-backup-<time>`, just before the dotfiles are linked. `djd apply --dry-run` moves nothing.
- A login zsh on a real terminal starts herdr. Export `DJD_NO_MUX=1` (for example in `~/.config/djd/profile.local`) to skip it.
- The `server` module's firewall denies every inbound port except SSH (rate-limited) and RDP from private networks. Docker's published ports bypass it (the module makes them bind to `127.0.0.1` by default), and mDNS multicast stays open.
- The `desktop` module sets the system locale to ja_JP.UTF-8.
- The cloud-init files set the timezone to Asia/Tokyo, and `cloud-init/multipass.yaml` also sets a Japanese keyboard layout (`layout: jp`, `ctrl:nocaps`).

Unauthenticated GitHub API limits can stop tool installs. mise reads `MISE_GITHUB_TOKEN`, so set it in the environment of the `sh` that runs the installer. A `docker compose` build reads `GITHUB_TOKEN` from the environment instead. The token needs no scope, and [SECURITY.md](SECURITY.md#github-tokens) says why a scoped one is a risk.

```sh
curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | MISE_GITHUB_TOKEN=<token> sh -s -- agent
```

From a checkout, run `./install.sh agent server`. `make init ARGS="agent server"` does the same but needs make, which a fresh Ubuntu cloud image may not include (`sudo apt-get install make` first). Without module arguments it re-applies the current selection, which on a fresh machine is the base config. To install your own fork, see [Fork](#fork).

After the install, log in again, because the login shell changes to zsh (and the `server` module adds you to the `docker` group). Then run `djd doctor`. On a machine with the base config and `agent`, a healthy result is:

```text
ok ubuntu
ok mise-config
ok login-shell
ok bootstrap
ok dotfiles
```

Doctor exits 1 and prints a `FAIL <check>: <reason>` line for each failed check. A machine with the `server` module also gets `ok sshd`, one with `desktop` gets `ok xrdp-tls` and `ok xrdp-root-login`, and one with `secrets` gets `ok secrets`. The five lines above are the output of `djd doctor` in the sandbox image.

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
| `desktop` | XFCE over xrdp (TLS only, no root login) with audio redirection (PipeWire), Japanese input (fcitx5-mozc), Noto CJK and HackGen NF fonts, ghostty, Brave, Zen Browser and Zed (all four required), system locale ja_JP.UTF-8 |
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

`djd secret set` writes into the checkout (`mise-config/config.secrets.toml`), and `djd` always acts on `~/.dotfiles`, so storing secrets needs `~/.dotfiles` to be a checkout of your own fork. To share secrets between machines:

1. Run `djd secret keygen` once. It writes the age key to `~/.config/djd/age.txt`.
2. Run `djd secret set NAME` for each value, for example `djd secret set GITHUB_TOKEN`. It prompts for the value.
3. Commit and push `mise-config/config.secrets.toml`. It holds ciphertext only.
4. Run `djd update` on every other machine.
5. Copy `~/.config/djd/age.txt` to every machine you own, by a channel that is not the repository.
6. Run `djd module add secrets` on those machines.

A stored value goes through `$VAR` and `{{ }}` expansion when it is read, so do not store one that contains `$` or `{{`. [SECURITY.md](SECURITY.md#age-encrypted-secrets) lists the limits of this design, and [docs/architecture.md](docs/architecture.md#secrets-use-the-age-support-of-mise) explains it.

## Desktop over RDP

```sh
cp .devcontainer/.env.example .devcontainer/.env   # set PASSWORD
mise run up
```

`make up` and `mise run up` are the same task and need the checkout trusted by mise (`mise trust`, once per clone). Without mise, run `docker compose -f .devcontainer/compose.yaml up -d --build desktop`.

| Command | Effect | Files, browser profiles and settings in the container |
| --- | --- | --- |
| `mise run up` | builds the image and starts the container | kept while the container stays. A rebuilt image makes compose replace the container, which drops them (compose behavior, not tested here) |
| `docker compose -f .devcontainer/compose.yaml stop desktop` | stops the container | kept |
| `mise run down` | removes the container | deleted |

A devcontainer mounts the whole checkout, so keep only the RDP password (and the optional tunnel token) in `.devcontainer/.env`, never GitHub or other tokens. A `PASSWORD` or `RDP_PORT` exported in your shell wins over that file.

Connect an RDP client to `localhost:33389` as `ubuntu`. The port is bound to `127.0.0.1` only. The tests use xfreerdp3; Windows App and mstsc were not tried against the TLS-only setting. The TLS certificate is new at every container start, so a client that remembers it on first use warns after each restart. [SECURITY.md](SECURITY.md#known-limits-of-the-rdp-service) lists this and the other known limits of the RDP service.

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
incus exec djd -- systemctl restart xrdp xrdp-sesman   # xrdp reads its TLS-only settings at start
incus list djd                    # connect an RDP client to this address, port 3389
```

The server module opens RDP only to loopback and private networks, and the incus bridge is private.

If the host runs ufw or Docker, which the `server` module sets up, the container gets no network until the host allows the bridge. The [Incus firewall guide](https://linuxcontainers.org/incus/docs/main/howto/network_bridge_firewalld/) lists the rules. For ufw, run:

```sh
sudo ufw allow in on incusbr0
sudo ufw route allow in on incusbr0
sudo ufw route allow out on incusbr0
```

For Docker, add two `iptables -I DOCKER-USER` rules, the ones in `.github/workflows/ci.yaml`, and make them persistent across reboots yourself.

multipass ([install it](https://documentation.ubuntu.com/multipass/latest/how-to-guides/install-multipass/) on macOS, Windows or Linux) installs `server desktop` at first boot and imports the `gh:dayjobdoor` SSH keys. In a fork, see [Fork](#fork) first:

```sh
multipass launch 26.04 --name djd --cpus 4 --memory 8G --disk 40G --timeout 3600 --cloud-init cloud-init/multipass.yaml   # waits for the install
multipass exec djd -- sudo passwd ubuntu   # RDP login needs a password
multipass exec djd -- sudo systemctl restart xrdp xrdp-sesman   # xrdp reads its TLS-only settings at start
multipass info djd                         # connect an RDP client to this address, port 3389
```

The default multipass size (1 CPU, 1 GB RAM, 5 GB disk) is too small for the desktop module. [docs/how-to.md](docs/how-to.md#try-it-in-an-orbstack-machine) covers OrbStack. `mise run test:vm` ran end to end on OrbStack 2.2.5 (arm64, macOS host) on 2026-11-01, with the server and desktop modules installed from `cloud-init/vm.yaml` on `ubuntu:resolute`. That run used an earlier tree, so the recipe and the test are verified on OrbStack but not on this exact commit.

## agentOS

The portable subset runs in a [Rivet agentOS](https://rivet.dev/docs/agent-os) VM. `agentos/boot.mjs` declares it, with `.profile`, the git config with an agentOS override, and WASM registry tools. The registry packages are pinned in `agentos/software.lock.json`, and the boot installs exactly those bytes. `tests/agentos-bundle.sh` checks that the command of every registry package exists in the sandbox image, so a command an agent finds in a guest exists there too. `agentos:boot` starts a native sidecar as your user. Run it in the sandbox image, as [Development](#development) shows, not on a machine you care about.

```sh
mise run agentos:export   # writes dist/agentos/bundle.json: the five files and the locked package URLs and digests
mise run agentos:boot     # boots a VM with the network denied and checks the bundle, shell, git config and tools
mise run agentos:lock     # re-pins the registry packages after a bump of agentos-core
```

## Remove

Run these in order. The first needs `djd`, which the second deletes. This exact sequence ran in the sandbox image with only `agent` selected.

```sh
djd module remove agent server desktop   # every module `djd module list` shows as selected
mise dot unapply --group home --yes      # the base dotfile links
sudo chsh -s /bin/bash "$USER"           # login shell back to bash
cp --update=none /etc/skel/.bashrc /etc/skel/.profile ~   # djd apply deleted the defaults these links replaced
rm ~/.config/mise                        # the link to this repository's mise config
rm -rf ~/.dotfiles                       # a clone; check `git -C ~/.dotfiles status` and push first. If it is a link to your own checkout, use `rm ~/.dotfiles` instead
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
mise run test:offline [test]          # the four offline tests on the current tree in an existing djd:sandbox, about 40 s and no build (also: make test:offline)
make test                             # builds the sandbox image, then the offline tests, doctor, PATH, shell startup, backup and checkout re-apply, secrets round trip
make test:desktop                     # desktop image: RDP login starts XFCE through ~/.xsession, xrdp-sink is the default audio sink, and brave, ghostty, zen and zed run
make test:vm                          # fresh incus, multipass or OrbStack VM: server + desktop install, hardening, module removal
make ci                               # every CI job act can run: lint, sandbox, desktop, agentos (ARGS=sandbox for one)
make ci ARGS=--dry-run                # plan every job of every workflow, release ones included
```

`make <task>` is `mise run <task>`, with a few exceptions that the [make targets](docs/reference.md#make-targets) section lists. Repo tools are pinned in `mise.lock`, and [docs/how-to.md](docs/how-to.md#update-the-pinned-tools) says how to update them. Tests that install or apply anything run in Docker or a throwaway VM, never on your machine. `make lint` runs on the host and installs its user-level tools there. `mise run agentos:boot` starts a native sidecar, so [AGENTS.md](AGENTS.md) runs it in the sandbox image. [docs/ci.md](docs/ci.md) says what each CI job proves, and AGENTS.md has the rules. A push or pull request that changes only Markdown, `docs/` or `llms.txt` skips `ci.yaml` and runs `lint:docs` in `docs.yaml` instead.

## Documentation

| Doc | Kind | Read when |
| --- | --- | --- |
| [docs/reference.md](docs/reference.md) | reference | you need a fact such as a file, command, variable, hook or image |
| [docs/how-to.md](docs/how-to.md) | how-to | you work on the repository, for example run CI, raise the mise release or publish a release |
| [docs/architecture.md](docs/architecture.md) | explanation | you want to know why the design is what it is |
| [docs/ci.md](docs/ci.md) | reference | you change a workflow or a test, or need to know what a CI job proves |
| [docs/history.md](docs/history.md) | explanation | you compare this repository with budybye/dotfiles or look for planned work |
| [SECURITY.md](SECURITY.md) | reference | you report a vulnerability, store a secret or judge a hardening claim |
| [AGENTS.md](AGENTS.md) | reference | you are a coding agent that changes this repository |
| [DESIGN.md](DESIGN.md) | reference | you change colors, fonts or theme names |
| [llms.txt](llms.txt) | reference | a tool needs an index of the docs |

## Issues and questions

Open an issue at [github.com/dayjobdoor/dotfiles/issues](https://github.com/dayjobdoor/dotfiles/issues). Report vulnerabilities as described in [SECURITY.md](SECURITY.md#reporting-a-vulnerability).

## License

[MIT](LICENSE)
