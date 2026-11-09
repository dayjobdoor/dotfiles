# References

Pointers before you search: the terms of this repository, the documentation of the parts it uses, and where each tool, app and action comes from. The decisions are in [architecture.md](architecture.md), the stack in [tech.md](tech.md).

## Terms

| Term | Meaning |
| --- | --- |
| VM | A fresh Ubuntu 26.04 machine with systemd that `test:vm` starts from `cloud-init/vm.yaml`. In CI it is an incus system container, which shares the runner's kernel. On a Mac it is a multipass machine. |
| part | One step of `mise bootstrap`, such as `packages`, `files`, `dotfiles`, or `tools`. `--only` and `--skip` take the part names. This is mise's word. |
| flavor | The set of modules that one Docker image installs, passed as `DJD_MODULES`. The published image is `agent` on the base, which includes the desktop. The `full` flavor, `agent full`, is built only by `full-weekly.yaml`. |
| checkout | The git working tree at `~/.dotfiles`, which can be a symlink to a tree elsewhere. `~/.config/mise` links to its `mise-config/`. |
| image test | A task that builds a Docker image and asserts inside containers of it. `test` and `test:desktop` test the one image. `test:vm` is the VM test. |
| module | A mise config environment, `mise-config/config.<module>.toml`, that `djd module add` selects. The base config always applies. The modules are `agent`, `server`, `full`, and `secrets`. The desktop is part of the base. |
| hook | A script that mise runs before or after a bootstrap part. The scripts are in `mise-config/hooks/`. |
| shim | A small executable in `~/.local/share/mise/shims` that runs the version of a tool that mise selects. |
| drop-in | A small file in a `*.d` directory that adds to or overrides the main config file, such as `/etc/ssh/sshd_config.d/10-djd.conf`. |
| dotfile group | The files under one top-level directory (only `home`) that mise links into `~`, one symlink per file. |
| drift | A difference between what the config declares and the state of the machine. `mise bootstrap status` and `djd doctor` report it. |
| converge | To apply the config until no drift is left. `djd apply` converges, and `djd doctor` together with `mise bootstrap plan --detailed-exitcode` tells whether it did. |
| floating tag | An image tag that moves to each new release, such as `latest` or `X.Y`. A fixed tag such as `X.Y.Z` is written once. |
| digest | The SHA-256 hash that names one exact image or file. |
| smoke test | A short run that shows the basics work. Here it is `djd doctor` in a pushed image. |
| attestation | A signed statement about how an image was built. The image index lists it as an `unknown/unknown` entry. |
| TOFU | Trust on first use. A client accepts a server's certificate the first time and warns when it changes. |
| NLA | Network Level Authentication. The RDP client proves who the user is before the session starts, through CredSSP. |
| CredSSP | The Windows protocol that carries the credentials of NLA. The xrdp of this repository offers none. |
| snakeoil | The self-signed placeholder key and certificate that the Ubuntu `ssl-cert` package makes when it is installed. |

## Documentation of the parts

| Part | Where to read |
| --- | --- |
| mise (bootstrap, dotfiles, tasks, settings, the cache) | [mise.jdx.dev](https://mise.jdx.dev) and its [cache behavior](https://mise.jdx.dev/cache-behavior.html) |
| sheldon, zsh-abbr, zsh-job-queue | [sheldon.cli.rs](https://sheldon.cli.rs), [olets/zsh-abbr](https://github.com/olets/zsh-abbr), [olets/zsh-job-queue](https://github.com/olets/zsh-job-queue) |
| age | [age-encryption.org](https://age-encryption.org) |
| cloud-init | [cloudinit.readthedocs.io](https://cloudinit.readthedocs.io) |
| multipass, incus | [multipass](https://documentation.ubuntu.com/multipass/latest/), [incus](https://linuxcontainers.org/incus/docs/main/) |
| Docker build | [docs.docker.com/build](https://docs.docker.com/build/) |
| GitHub Actions | [docs.github.com/actions](https://docs.github.com/actions) |
| xrdp | [neutrinolabs/xrdp](https://github.com/neutrinolabs/xrdp) |
| The desktop apps | [Brave](https://brave.com), [Wireshark](https://www.wireshark.org), [Zed](https://zed.dev), [Zen](https://zen-browser.app), [Obsidian](https://obsidian.md), [Vicinae](https://vicinae.com), [Ferdium](https://ferdium.org) |

## Tools and repositories

Where each tool and project comes from. The versions are in the configs: `latest` tools resolve at install time, the pinned `http:` tools carry a version and a checksum in `mise-config/config.toml`, and `.mise/mise.lock` pins the repo's own tools. `mise registry <name>` shows the backend that mise uses for a name.

### This repository

| What | Where |
| --- | --- |
| Source | [dayjobdoor/dotfiles](https://github.com/dayjobdoor/dotfiles) |
| Image | `ghcr.io/dayjobdoor/dotfiles` ([package page](https://github.com/dayjobdoor/dotfiles/pkgs/container/dotfiles)) |
| Releases | [dayjobdoor/dotfiles releases](https://github.com/dayjobdoor/dotfiles/releases) |
| mise | [mise.jdx.dev](https://mise.jdx.dev), [jdx/mise](https://github.com/jdx/mise) |
| Report a vulnerability | [SECURITY.md](../SECURITY.md#reporting-a-vulnerability) |

### Base tools (`mise-config/config.toml`)

| Tool | Repository | Note |
| --- | --- | --- |
| `usage` | [jdx/usage](https://github.com/jdx/usage) |  |
| `starship` | [starship/starship](https://github.com/starship/starship) |  |
| `zoxide` | [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide) |  |
| `fzf` | [junegunn/fzf](https://github.com/junegunn/fzf) |  |
| `ripgrep` | [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) |  |
| `fd` | [sharkdp/fd](https://github.com/sharkdp/fd) |  |
| `bat` | [sharkdp/bat](https://github.com/sharkdp/bat) |  |
| `lsd` | [lsd-rs/lsd](https://github.com/lsd-rs/lsd) |  |
| `sd` | [chmln/sd](https://github.com/chmln/sd) |  |
| `jq` | [jqlang/jq](https://github.com/jqlang/jq) |  |
| `yq` | [mikefarah/yq](https://github.com/mikefarah/yq) |  |
| `delta` | [dandavison/delta](https://github.com/dandavison/delta) |  |
| `gh` | [cli/cli](https://github.com/cli/cli) |  |
| `lazygit` | [jesseduffield/lazygit](https://github.com/jesseduffield/lazygit) |  |
| `jj` | [jj-vcs/jj](https://github.com/jj-vcs/jj) |  |
| `jj-starship` | [dmmulroy/jj-starship](https://github.com/dmmulroy/jj-starship) |  |
| `bottom` | [ClementTsang/bottom](https://github.com/ClementTsang/bottom) |  |
| `micro` | [micro-editor/micro](https://github.com/micro-editor/micro) |  |
| `herdr` | [herdrdev/herdr](https://github.com/herdrdev/herdr) |  |
| `shellcheck` | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) |  |
| `shfmt` | [mvdan/sh](https://github.com/mvdan/sh) |  |
| `sheldon` | [rossmacarthur/sheldon](https://github.com/rossmacarthur/sheldon) |  |
| `ruby` | [ruby/ruby](https://github.com/ruby/ruby) |  |
| `fusuma (gem)` | [iberianpig/fusuma](https://github.com/iberianpig/fusuma) |  |

### Desktop apps and system programs

| Tool | Repository | Source |
| --- | --- | --- |
| `zed` | [zed-industries/zed](https://github.com/zed-industries/zed) | `github:` tool, latest |
| `zen` | [zen-browser/desktop](https://github.com/zen-browser/desktop) | `github:` tool, latest |
| `hackgen` | [yuru7/HackGen](https://github.com/yuru7/HackGen) | `http:` tool, pinned, SHA-256 |
| `obsidian` | [obsidianmd/obsidian-releases](https://github.com/obsidianmd/obsidian-releases) | `http:` tool, pinned, SHA-256 |
| `vicinae` | [vicinaehq/vicinae](https://github.com/vicinaehq/vicinae) | `http:` tool, pinned, SHA-256 |
| `ferdium` | [ferdium/ferdium-app](https://github.com/ferdium/ferdium-app) | `http:` tool, pinned, SHA-256 |
| `ghostty` | [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) | Ubuntu archive (`apt`) |
| `xrdp` | [neutrinolabs/xrdp](https://github.com/neutrinolabs/xrdp) | Ubuntu archive (`apt`) |
| `brave-browser` | [brave.com](https://brave.com) | Brave's apt repository |
| `wireshark` | [wireshark.org](https://www.wireshark.org) | Ubuntu archive (`apt`) |
| XFCE, PipeWire, fcitx5-mozc and the other packages | [packages.ubuntu.com](https://packages.ubuntu.com/resolute/) | Ubuntu archive (`apt`), listed in [Modules](tech.md#modules) |

### `agent` and `server` modules

| Tool | Repository | Note |
| --- | --- | --- |
| `node` | [nodejs/node](https://github.com/nodejs/node) |  |
| `bun` | [oven-sh/bun](https://github.com/oven-sh/bun) |  |
| `python` | [python/cpython](https://github.com/python/cpython) |  |
| `uv` | [astral-sh/uv](https://github.com/astral-sh/uv) |  |
| `pi` | [earendil-works/pi](https://github.com/earendil-works/pi) |  |
| `omp (oh-my-pi)` | [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) |  |
| `skills` | [vercel-labs/skills](https://github.com/vercel-labs/skills) |  |
| `lazydocker` | [jesseduffield/lazydocker](https://github.com/jesseduffield/lazydocker) | `server` module |

The `full` module's tools are listed in `mise-config/config.full.toml`, one per line.

### Tools of the repository itself (`.mise/tasks/`)

| Tool | Repository | Note |
| --- | --- | --- |
| `act` | [nektos/act](https://github.com/nektos/act) |  |
| `jactionlint` | [jdx/jactionlint](https://github.com/jdx/jactionlint) |  |
| `hadolint` | [hadolint/hadolint](https://github.com/hadolint/hadolint) |  |
| `gitleaks` | [gitleaks/gitleaks](https://github.com/gitleaks/gitleaks) |  |
| `shellcheck` | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) |  |
| `shfmt` | [mvdan/sh](https://github.com/mvdan/sh) |  |
| `@google/design.md` | [google-labs-code/design.md](https://github.com/google-labs-code/design.md) |  |

### GitHub Actions

Every `uses:` in `.github/workflows/` is pinned to a commit; the table gives the release that the comment beside each pin names. Dependabot moves them, after a cooldown of seven days.

| Action | Release |
| --- | --- |
| [actions/checkout](https://github.com/actions/checkout) | v7.0.1 |
| [jdx/mise-action](https://github.com/jdx/mise-action) | v5.2.6 |
| [docker/setup-buildx-action](https://github.com/docker/setup-buildx-action) | v4.4.1 |
| [docker/login-action](https://github.com/docker/login-action) | v4.7.0 |
| [docker/metadata-action](https://github.com/docker/metadata-action) | v6.2.0 |
| [docker/build-push-action](https://github.com/docker/build-push-action) | v7.4.0 |
| [actions/upload-artifact](https://github.com/actions/upload-artifact) | v7.0.2 |
| [actions/download-artifact](https://github.com/actions/download-artifact) | v8.0.2 |
