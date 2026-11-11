# dotfiles

[![CI](https://github.com/dayjobdoor/dotfiles/actions/workflows/ci.yaml/badge.svg)](https://github.com/dayjobdoor/dotfiles/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Ubuntu 26.04](https://img.shields.io/badge/Ubuntu-26.04-E95420?logo=ubuntu&logoColor=white)
[![mise](https://img.shields.io/badge/managed%20by-mise-6f42c1)](https://mise.jdx.dev)

Ubuntu 26.04 dotfiles for coding-agent machines, servers and VMs, every one with an XFCE desktop over RDP, managed entirely by [mise](https://mise.jdx.dev). One `mise bootstrap` installs apt packages, writes system files, configures the firewall, links dotfiles, sets the login shell and installs tools. `djd` is a small CLI on top.

Jump to: [Start](#start), [Modules](#modules), [djd](#djd), [Remove](#remove), [Fork](#fork), [Development](#development), [Documentation](#documentation).

- **One tool.** No chezmoi, Ansible or Stow. The repo is the global mise config, and every machine role is a mise config environment.
- **Modules, not forks.** `agent`, `server`, `full`, `warp` and `secrets` add up per machine, on top of a base that includes the desktop, and come off again with `djd module remove`.
- **Tested end to end.** CI builds the images on amd64 and arm64, logs in over RDP, and installs the base, the server module and the warp module into a fresh incus system container (incus runs Linux containers and VMs).
- **Public by design.** Secrets are committed only as age ciphertext, workflows are audited by jactionlint and pinned to commits, and gitleaks scans the history in CI and the staged changes in an opt-in pre-commit hook.

## Start

Pick where it runs. All of them end in the same Ubuntu 26.04 machine with the base (zsh, tools, the XFCE desktop over RDP) and the modules you chose.

| Where | You get | Read |
| --- | --- | --- |
| an Ubuntu 26.04 machine you already have | the base and the modules you name | [Install on a machine](#install-on-a-machine) |
| Docker (also OrbStack's Docker on a Mac) | one image: the base and `agent`, a shell or the desktop over RDP | [Docker](#docker) |
| multipass (macOS, Windows, Linux) | a VM with the base and `server` | [multipass](#multipass) |
| incus (Linux) | a system container with the base and `server` | [incus](#incus) |

The VM recipes install the `server` module (sshd, firewall, docker) on a machine with systemd; the Docker image has no systemd and no `server` module. [architecture.md](docs/architecture.md#a-container-and-a-vm-differ-in-three-things-only) lists the three differences. Every target uses the user `dayjobdoor`; the VM recipes name the machine `vm` and compose names the container `container`. The desktop needs a password for RDP, and none is committed ([SECURITY.md](SECURITY.md#the-desktop)), so each recipe sets one.

## Install on a machine

On a machine that already runs Ubuntu 26.04 (amd64 or arm64), as a user with sudo:

```sh
curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | sh -s -- agent
```

What it changes on the machine:

- `TZ` defaults to Asia/Tokyo in `~/.profile`. Override it in `~/.config/djd/profile.local`.
- zsh becomes the login shell, and the `server` module adds your user to the `docker` group. Both need a new login.
- A real file that a dotfile would replace is moved to `<file>.djd-backup-<epoch>-<pid>` just before the dotfiles are linked ([how](docs/tech.md#bootstrap-phases-and-hooks)). `djd apply --dry-run` moves nothing.
- A login zsh on a real terminal starts herdr, a terminal multiplexer (panes and a sidebar) that hosts the pi and omp coding agents, through `herdr-dev`, which also creates a dev workspace with a few tabs (`btm`, `fastfetch`, a dev layout, pi and lazydocker where they exist). Export `DJD_NO_MUX=1` (for example in `~/.config/djd/profile.local`) to skip it.
- The `server` module's firewall denies every inbound port except SSH (rate-limited) and RDP from private networks. Docker's published ports bypass it (the module makes them bind to `127.0.0.1` by default), and mDNS multicast stays open.
- The `server` module turns password and root logins off for ssh. Its `post-packages` hook refuses to continue when your user has no key in `~/.ssh/authorized_keys`, when the apply runs as root, or when sshd listens on a port other than 22, because each would lock you out. `DJD_SKIP_SSH_CHECKS=1` skips the refusals on a machine that you reach another way (a console, `incus exec`, `multipass exec`).
- The system locale stays `C.UTF-8`, so agents and ssh logins get English output. Only the RDP desktop session is Japanese (`~/.xsession` sets `LANG=ja_JP.UTF-8`).
- Every machine runs xrdp (TLS only) on 3389/tcp. Without the `server` module nothing limits it to loopback and private networks, and `djd module add` warns about that.
- `cloud-init/vm.yaml` sets the timezone to Asia/Tokyo and a Japanese keyboard layout (`layout: jp`, `ctrl:nocaps`).

Anonymous GitHub API limits can stop tool installs. mise reads `MISE_GITHUB_TOKEN`, so set it in the environment of the `sh` that runs the installer. A `docker compose` build reads `GITHUB_TOKEN` from the environment instead. The token needs no scope, and [SECURITY.md](SECURITY.md#github-tokens) says why a scoped one is a risk.

```sh
curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | MISE_GITHUB_TOKEN=<token> sh -s -- agent
```

From a checkout, run `./install.sh agent server`. Without module arguments it re-applies the current selection, which on a fresh machine is the base config. To install your own fork, see [Fork](#fork).

After the install, log in again, because the login shell changes to zsh (and the `server` module adds you to the `docker` group). Then run `djd doctor`. On a machine with the base config and `agent`, a healthy result is:

```text
ok ubuntu
ok mise-config
ok login-shell
ok bootstrap
ok dotfiles
ok plugins
ok xrdp-tls
ok xrdp-root-login
```

Doctor exits 1 and prints a `FAIL <check>: <reason>` line for each failed check. A machine with the `server` module also gets `ok sshd`, and one with `secrets` gets `ok secrets`. The lines above are the output of `djd doctor` in the image.

## Docker

The image is the base (with the desktop) and the `agent` module. It has no sshd, firewall or docker daemon. A shell in it, from GHCR:

```sh
docker run --rm -it --init ghcr.io/dayjobdoor/dotfiles:latest
```

The desktop over RDP runs from a clone of this repository, through compose:

```sh
git clone https://github.com/dayjobdoor/dotfiles && cd dotfiles
cp .devcontainer/.env.example .devcontainer/.env   # set PASSWORD
mise run up                                         # or: docker compose -f .devcontainer/compose.yaml up -d --build --wait ubuntu
```

`--wait` makes the command fail when the container does not become healthy (the compose healthcheck is xrdp listening), as it does with an empty `PASSWORD`, which the entrypoint refuses. Connect an RDP client to `localhost:3589` as `dayjobdoor` with that `PASSWORD`. The port is bound to `127.0.0.1` only. The image has xfreerdp3 (`xfreerdp3 /v:localhost:3589 /u:dayjobdoor`), which `test:desktop` also uses, in a client container of its own; Windows App and mstsc were not tried against the TLS-only setting. The TLS certificate is new at every container start, so a client that remembers it on first use warns after each restart. [SECURITY.md](SECURITY.md#known-limits-of-the-rdp-service) lists this and the other known limits of the RDP service.

`mise run up` needs the checkout trusted by mise (`mise trust`, once per clone). The compose build reads `GITHUB_TOKEN` from the environment, a token without scopes or an empty one. Unlike `mise run build`, `mise run up` and the devcontainer do not stop when it is unset; the tool installs then run anonymously, and the API limit can stop them.

| Command | Effect | Files, browser profiles and settings in the container |
| --- | --- | --- |
| `mise run up` | builds the image and starts the container | kept while the container stays. When the image is rebuilt, compose replaces the container, and the new one has none of them (compose behavior, not tested here) |
| `docker compose -f .devcontainer/compose.yaml stop ubuntu` | stops the container | kept |
| `mise run down` | removes the container | deleted |

A devcontainer mounts the whole checkout, so keep only the RDP password (and the optional tunnel token) in `.devcontainer/.env`, never GitHub or other tokens. A `PASSWORD` exported in your shell wins over that file.

## VMs

The multipass and incus recipes read `cloud-init/vm.yaml`, so run them from a clone of this repository. Above its `# djd-install-below` line the file sets the machine up: hostname `vm`, the user `dayjobdoor` with passwordless sudo, the timezone, a Japanese keyboard layout (`layout: jp`, `ctrl:nocaps`) and the packages. Below it, it imports your SSH keys and runs the install. In a fork, change the GitHub user there first ([Fork](#fork)). After the install, the VM is a machine like any other: log in, and run `djd doctor`.

### multipass

[Install multipass](https://documentation.ubuntu.com/multipass/latest/how-to-guides/install-multipass/) on macOS, Windows or Linux. The launch installs the `server` module at first boot and waits for it. The RDP password goes in as a hash at launch, so no password is committed; `openssl` asks for it:

```sh
hash=$(openssl passwd -6)
{ cat cloud-init/vm.yaml; printf 'chpasswd:\n  expire: false\n  users:\n    - {name: dayjobdoor, password: %s, type: hash}\n' "$hash"; } |
    multipass launch 26.04 --name vm --cpus 4 --memory 8G --disk 40G --timeout 3600 --cloud-init -   # waits for the install
multipass info vm                        # connect an RDP client to this address, port 3389, as dayjobdoor with that password
multipass shell vm                       # logs in as the default user ubuntu; `sudo -iu dayjobdoor` switches to dayjobdoor
multipass delete --purge vm              # when you are done
```

The default size (1 CPU, 1 GB RAM, 5 GB disk) is too small for the desktop. Without the `chpasswd` block `dayjobdoor` has no password and an RDP login fails; `sudo passwd dayjobdoor` inside the VM sets one afterwards. The key import asks GitHub's API, which limits anonymous callers; when it is refused, the server module stops the install at its key check ([SECURITY.md](SECURITY.md#github-tokens) explains tokens).

### incus

incus runs a system container with systemd on Linux. `security.nesting` lets the server module run Docker in it. The first three commands set incus up once on Ubuntu 26.04, and the group change needs a new login:

```sh
sudo apt install incus-base incus-client   # once
sudo incus admin init --minimal            # once
sudo adduser "$USER" incus-admin           # once, then log in again
incus launch images:ubuntu/26.04/cloud vm -c security.nesting=true -c cloud-init.user-data="$(sed '/^# djd-install-below$/,$d' cloud-init/vm.yaml)"
incus exec vm -- cloud-init status --wait
incus exec vm -- sudo -iu dayjobdoor sh -c 'curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | DJD_SKIP_SSH_CHECKS=1 sh -s -- server'
incus exec vm -- passwd dayjobdoor   # RDP login needs a password
incus list vm                    # connect an RDP client to this address, port 3389
```

The `sed` leaves out the key import and the install, which the next commands do by hand. `DJD_SKIP_SSH_CHECKS=1` is there because the container has no authorized ssh key, and the server module refuses to turn passwords off for a user without one. The install restarts xrdp itself, so it reads its TLS-only settings. The server module opens RDP only to loopback and private networks, and the incus bridge is private.

If the host runs ufw or Docker, which the `server` module sets up, the container gets no network until the host allows the bridge. The [Incus firewall guide](https://linuxcontainers.org/incus/docs/main/howto/network_bridge_firewalld/) lists the rules. For ufw, run:

```sh
sudo ufw allow in on incusbr0
sudo ufw route allow in on incusbr0
sudo ufw route allow out on incusbr0
```

For Docker, add two `iptables -I DOCKER-USER` rules, the ones in `.github/workflows/ci.yaml`, and make them persistent across reboots yourself.

## Modules

| Module | Adds |
| --- | --- |
| base | zsh, git, make, core CLI tools (ripgrep, fd, jq, gh, lazygit, jj, starship, herdr, …), dotfiles, and the desktop: XFCE over xrdp (TLS only, no root login) with an RDP client (xfreerdp3), audio redirection (PipeWire), Japanese input (fcitx5-mozc), Noto CJK and HackGen NF fonts, ghostty, Brave, Zen Browser and Zed (all four required), Wireshark, Obsidian, Vicinae, Ferdium and fusuma |
| `agent` | node, bun, python, uv, build tools, the coding agents pi and omp (oh-my-pi), the `skills` CLI for agent skills, the global instructions of pi and omp (`AGENTS.md` for pi, `RULES.md` for omp), telemetry off |
| `server` | openssh-server (keys only), avahi, ufw firewall (RDP from private networks only), docker (published ports on `127.0.0.1` by default); see [SECURITY.md](SECURITY.md#server-module) |
| `full` | the whole personal toolbox (172 tools; plan for at least 10 GB of disk, an estimate that [tech.md](docs/tech.md#modules) explains); implies `agent` |
| `warp` | Cloudflare WARP (`cloudflare-warp`, from Cloudflare's apt repository); for VMs and real hosts, not the container; register once with `warp-cli registration new` and `warp-cli connect` |
| `secrets` | your age-encrypted environment secrets; only for machines you own |

## djd

```sh
djd                       # list commands; djd module --help and djd secret --help show their arguments
djd apply                 # converge this machine to the repo
djd update                # pull, update mise, upgrade packages and tools
djd status                # checkout, modules, bootstrap state
djd doctor                # health check, exit 1 on failure
djd module list
djd module add server
djd module remove server  # packages stay installed
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

## Remove

Run these in order. The first command needs `djd`, and the second removes its link, `~/.local/bin/djd`. This exact sequence ran in the image with only `agent` selected.

```sh
djd module remove agent server           # every module `djd module list` shows as selected
mise dot unapply --group home --yes      # the base dotfile links
sudo chsh -s /bin/bash "$USER"           # login shell back to bash
cp --update=none /etc/skel/.bashrc /etc/skel/.profile ~   # djd apply deleted the defaults these links replaced
rm ~/.config/mise                        # the link to this repository's mise config
rm -rf ~/.dotfiles                       # a clone; check `git -C ~/.dotfiles status` and push first. If it is a link to your own checkout, use `rm ~/.dotfiles` instead
```

`~/.local/share/mise` and `~/.local/bin/mise` hold mise and the installed tools. These also stay, and you delete them by hand if you want them gone: `~/.config/djd` (your age key `age.txt`, `profile.local` and `bashrc.local`), `~/.local/state/djd` (the restart and sshd stamps), the zsh plugin checkouts in `~/.local/share/sheldon`, `~/.cache/zsh` and `~/.cache/bash`, and what the base wrote outside the home: `/etc/locale.conf`, `/etc/apt/apt.conf.d/90djd-conffiles`, `/etc/apparmor.d/djd-electron`, the `wireshark` and `input` group memberships, and the HackGen font and the app menu entries and icons under `~/.local/share`. Packages, ufw rules and the `docker` group stay; remove them with `apt`, `ufw` and `gpasswd -d "$USER" docker`. Files moved aside as `*.djd-backup-*` are yours to move back. Removing `server` brings back password logins and published ports on every address, and `djd module remove` prints a warning ([tech.md](docs/tech.md#modules) has the details).

## Fork

Replace `dayjobdoor` with your GitHub user (`git grep -l dayjobdoor` lists the files). These places matter.

- `DJD_REPO` in `install.sh`. A fork's raw `install.sh` still clones the original repository unless this changes. The variable can also be set in the environment for one run.

To install a fork, take `install.sh` from the fork and name the fork's clone URL:

```sh
curl -fsSL https://raw.githubusercontent.com/<you>/dotfiles/main/install.sh | DJD_REPO=https://github.com/<you>/dotfiles.git sh -s -- agent
```

The fork has no GHCR images until it publishes a release. [Publish the first release](docs/guidance.md#publish-the-first-release) lists the steps.

These places also matter:

- `REGISTRY_IMAGE` in `.github/workflows/push.yaml`, in lowercase.
- The GitHub user in `ssh-import-id` and the install URL in `runcmd` in `cloud-init/vm.yaml`, and the user `dayjobdoor`.
- The `origin` URL and the dry-run `full_name` that `.mise/tasks/ci` sets for act.

## Development

```sh
export GITHUB_TOKEN=                  # build, test, test:desktop and ci stop without it: a token with no scopes, or empty for none (SECURITY.md#github-tokens)
git config core.hooksPath .githooks   # gitleaks on every commit
mise trust                            # once per clone, by you on a machine you accept it on (AGENTS.md bans it elsewhere)
mise tasks ls                        # list tasks
mise run lint                        # shell, mise configs, workflows + Dockerfile, DESIGN.md, docs links and secrets, in parallel
mise run lint:fix                    # rewrite shell and mise TOML formatting
mise run test:offline [test]         # the eight offline tests on the current tree in an existing djd:latest with no network and no build
mise run test                        # builds the image, then the offline tests, doctor, PATH, shell startup, backup and checkout re-apply, secrets round trip
mise run test:desktop                # the image: RDP login starts XFCE through ~/.xsession, xrdp-sink is the default audio sink, and brave, ghostty, zen and zed run
mise run test:vm                     # fresh incus or multipass VM: base, server and warp install, hardening, module removal
mise run ci                          # every CI job act can run: lint and image
mise run ci image                    # one CI job
mise run ci --dry-run                # plan every job of ci, docs, full-weekly, tag and push, release ones included
```

Repo tasks run through `mise run`; [repository tasks](docs/tech.md#repository-tasks) lists them. Repo tools are pinned in `.mise/mise.lock`, and [docs/guidance.md](docs/guidance.md#update-the-pinned-tools) says how to update them. [docs/testing.md](docs/testing.md) says what each CI job proves, and AGENTS.md has the rules, including where tests may run. A push or pull request that changes only Markdown, `docs/` or `llms.txt` skips `ci.yaml` and runs `docs.yaml` instead, except for `DESIGN.md` (both run) and the Markdown under `home/.config/pi` and `home/.config/omp` (only `ci.yaml` runs) ([maintenance.md](docs/maintenance.md#workflows)).

## Documentation

| Doc | Kind | Read when |
| --- | --- | --- |
| [docs/requirements.md](docs/requirements.md) | requirements | you want to know what ships, what does not, and what done looks like |
| [docs/architecture.md](docs/architecture.md) | explanation | you want to know how it is built and why the design is what it is |
| [docs/tech.md](docs/tech.md) | reference | you need the stack, a rejected option, or a lookup table: modules, `djd` commands, hooks, shell files, variables, images |
| [docs/directory.md](docs/directory.md) | reference | you need to know where a file lives, which names are allowed and which paths never enter the repository |
| [docs/problems.md](docs/problems.md) | reference | something behaves oddly, or you judge a limit such as the RDP security |
| [docs/references.md](docs/references.md) | reference | you look for a term, the documentation of a part, or the repository of a tool |
| [docs/guidance.md](docs/guidance.md) | how-to | you work on the repository, for example run CI, raise the mise release, update the pinned agent extensions or publish a release |
| [docs/maintenance.md](docs/maintenance.md) | reference | you change a workflow, cut a release or need the release chain |
| [docs/testing.md](docs/testing.md) | reference | you change a test, or need to know what a CI job proves |
| [ROADMAP.md](ROADMAP.md) | plan | you look for planned work by horizon |
| [CHANGELOG.md](CHANGELOG.md) | history | you want to know what a release changed |
| [SECURITY.md](SECURITY.md) | reference | you report a vulnerability, store a secret or judge a hardening claim |
| [AGENTS.md](AGENTS.md) | reference | you are a coding agent that changes this repository |
| [DESIGN.md](DESIGN.md) | reference | you change colors, fonts or theme names |
| [llms.txt](llms.txt) | reference | a tool needs an index of the docs |

## Issues and questions

Open an issue at [github.com/dayjobdoor/dotfiles/issues](https://github.com/dayjobdoor/dotfiles/issues). Report vulnerabilities as described in [SECURITY.md](SECURITY.md#reporting-a-vulnerability).

## License

[MIT](LICENSE)
