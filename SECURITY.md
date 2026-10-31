# Security

This repository is public. Treat every tracked file as published.

## Reporting a vulnerability

Use GitHub private vulnerability reporting (Security tab of the repository, then "Report a vulnerability"). Do not open a public issue. Reporting needs the repository's private vulnerability reporting setting enabled.

## Never commit

- `.env` / `.env.*` (only `.env.example` is tracked)
- tokens of any kind (GitHub, Cloudflare Tunnel, API keys)
- `gh/hosts.yml`, `rclone/rclone.conf`, `auth.json`
- private keys (`*.pem`, `*.key`, `~/.ssh/*`, age identities such as `age.txt`)
- `passwd:` entries in cloud-init files
- account IDs in agent configs (pi, omp)

`.gitignore` and `.dockerignore` cover the common file names; the checks below catch the rest.

## Local overrides

All of these are outside the repo or gitignored. The shell and git files are read when present.

| File | Purpose |
| --- | --- |
| `~/.config/djd/profile.local` | extra environment, loaded at the end of `~/.profile`. Every zsh, login bash and interactive bash reads it; `sh -c` and a non-login, non-interactive `bash -c` do not |
| `~/.config/zsh/.zshrc.local` | interactive zsh additions |
| `~/.config/djd/bashrc.local` | interactive bash additions |
| `~/.config/git/user.conf` | git identity and signing key |
| `~/.config/mise/miserc.local.toml` | module selection (gitignored inside `mise-config/`) |
| `.devcontainer/.env` | Compose values `PASSWORD` and `RDP_PORT`, and `TUNNEL_TOKEN` if you use the optional tunnel in `compose.yaml`. A devcontainer mounts the whole checkout, so an agent inside it can read this file: put nothing else in it, and no GitHub or other tokens |
| `~/.config/djd/age.txt` | age identity that decrypts the secrets module |

## age-encrypted secrets

`mise-config/config.secrets.toml` is the one place where secret values are committed, and only as age ciphertext written by `djd secret set`.

- The identity lives at `~/.config/djd/age.txt` (mode 600), outside the checkout. `age.txt` is ignored by git and Docker anyway, because mise's default key path `~/.config/mise/age.txt` is this repo's `mise-config/`.
- Ciphertext in a public repo is safe only while the key is. Keep the key off machines that run untrusted code. Back it up offline; losing every copy loses the values.
- Select the `secrets` module only on machines you own. Every process there sees the decrypted values, agents included. The Docker images never select it.
- Rotating a key means re-running `djd secret set` for each value on a machine that holds the new key.

## GitHub tokens

- Tool installs read public releases. A token only lifts the anonymous rate limit and needs no scope: use a classic token with no scopes or a fine-grained token with no permissions. `gh auth token` also works, but it hands the install step, which runs third-party tooling, every scope your login has. mise reads the token that `gh auth login` stores, because `github.gh_cli_tokens` is on by default, so a machine with a logged-in `gh` already sends that token on installs.
- Workflows run with `contents: read`. `GITHUB_TOKEN` goes to the one step that needs it, not the whole job; `lint` and `agentos` install from `mise.lock` (`MISE_LOCKED`) and get no token. Only `tag.yaml` (`contents: write`, `actions: write`) and `push.yaml` (`packages: write`) can write, and `tag.yaml` accepts only successful push runs of this repository's `main`.
- The release build passes the `packages: write` token to the install step as a BuildKit secret, so code that an upstream tool runs while installing could read it. `minimum_release_age = "3d"` in `mise-config/config.toml` keeps brand-new releases out of the image.
- A token stored with `djd secret set GITHUB_TOKEN` is visible to every process on that machine. Store a read-only one.

## Docker

- Tokens enter builds only through a BuildKit secret: `--secret id=github_token,env=GITHUB_TOKEN`, mounted as `MISE_GITHUB_TOKEN` for the package and tool install layer alone. Never pass tokens through `ARG` or `ENV`; both persist in image metadata.
- The sandbox image runs as the `ubuntu` user, not root. That user has passwordless sudo because the container is the isolation boundary. The desktop image runs xrdp as root (`user: root` in `.devcontainer/compose.yaml`).
- The desktop image takes its RDP password at container start, never at build time. The password is a container argument (`command` in `compose.yaml`), so anyone with Docker access can read it with `docker inspect`.
- Compose publishes RDP on `127.0.0.1` (`ports` in `compose.yaml`). The image itself does not restrict where the port is published.

## Server module

- SSH accepts keys only (`/etc/ssh/sshd_config.d/10-djd.conf`: no passwords, no keyboard-interactive, no root login). Each `djd apply` fails if another setting overrides the drop-in. Install your public key before you select `server` on a machine you reach over password SSH, or you lock yourself out.
- ufw denies incoming by default, rate-limits 22/tcp, and opens RDP (3389/tcp) only to private networks (10/8, 172.16/12, 192.168/16, and IPv6 fc00::/7 and fe80::/10). Reach RDP from anywhere else through `ssh -L 33389:localhost:3389 <host>`.
- `/etc/docker/daemon.json` binds published container ports to `127.0.0.1` when `-p` names no address, because Docker's port rules bypass ufw. Publish to the network on purpose with `-p 0.0.0.0:8080:80`. Networks created before the module was applied keep their old default.
- `djd module remove server` deletes the sshd drop-in and `daemon.json`; the firewall rules stay.

## Desktop module

- xrdp keeps the defaults of the Ubuntu 26.04 package (xrdp 0.10.1, read in a container). It listens on 3389/tcp on every interface, `security_layer=negotiate` lets a client fall back from TLS, `AllowRootLogin=true` in `sesman.ini`, and `MaxLoginRetry=4` is the only limit on password guesses. Ubuntu locks the root password by default, so root cannot log in over RDP.
- The firewall rules for RDP belong to the server module. A machine with `desktop` and without `server` has no firewall rule, so keep it off untrusted networks. `djd module add desktop` prints a warning in that case.

## Checks

- `.githooks/pre-commit` runs gitleaks on staged changes. Enable it once per clone with `git config core.hooksPath .githooks`.
- `mise run lint` (the CI `lint` job) scans the whole git history with gitleaks, or the files when there is no git directory, and audits the workflows with jactionlint (token persistence, dangerous triggers, cache poisoning, unpinned actions).
- Repo tools install from `mise.lock`, which pins each version and its checksum. Dependabot proposes updates to the pinned action SHAs.
- The zsh plugins that sheldon loads are pinned to commits in `home/.config/sheldon/plugins.toml`, so a new machine does not run whatever a default branch holds that day. Update a pin on purpose.
- `mise run ci` gives act a copy of tracked and unignored files only (`tests/tree.sh`); act's `.secrets` and `.vars` files are gitignored and dockerignored.
- Release images are built without a build cache.

## If a secret leaks

1. Rotate or revoke it first. A pushed secret is compromised even if the commit is removed.
2. Then purge it from history (`git filter-repo`) and force-push.
