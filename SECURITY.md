# Security

This repository is public. Treat every tracked file as published.

## Reporting a vulnerability

Use GitHub private vulnerability reporting (Security tab of the repository, then "Report a vulnerability"). Do not open a public issue. Reporting needs the repository's private vulnerability reporting setting enabled.

## Never commit

- `.env` / `.env.*` (only the `.env.example` files are tracked, one at the root and one in `.devcontainer/`). The root `.env` is for agent provider and GitHub tokens. It is gitignored and dockerignored, but a devcontainer mounts the whole checkout, so an agent inside one can read it
- tokens of any kind (GitHub, Cloudflare Tunnel, API keys)
- `gh/hosts.yml`, `rclone/rclone.conf`, `auth.json`
- private keys (`*.pem`, `*.key`, `~/.ssh/*`, age identities such as `age.txt`)
- `passwd:` entries in cloud-init files
- account IDs in agent configs (pi, omp)

`.gitignore` and `.devcontainer/Dockerfile.dockerignore` cover the common file names, and gitleaks (see Checks below) scans for secret patterns. Nothing checks for a `passwd:` entry in cloud-init or an account ID in an agent config beyond the two ignored `models` files, so review those by hand.

## Local overrides

All of these are outside the repo or gitignored. The shell and git files are read when present.

| File | Purpose |
| --- | --- |
| `~/.config/djd/profile.local` | extra environment, loaded at the end of `~/.profile`. Every zsh, login bash and interactive bash reads it; `sh -c` and a non-login, non-interactive `bash -c` do not. A value here does not reach shimmed tools when the same name is set in a module's `[env]`, because mise's `[env]` wins (use `config.local.toml` for those) |
| `~/.config/mise/config.local.toml` | overrides the `[env]` values and settings of the modules, for example `NPM_CONFIG_CACHE` or `DO_NOT_TRACK`. The file sits in `mise-config/`, and `*.local.toml` is gitignored and dockerignored |
| `~/.config/pi/agent/models.json`, `~/.config/omp/profiles/god/agent/models.yml` | the model lists of pi and omp. Their baseUrls hold a Cloudflare account ID, so the repository does not ship them: create them by hand, as real files next to the linked ones. They are gitignored under `home/` as well. |
| `~/.config/zsh/.zshrc.local` | interactive zsh additions |
| `~/.config/djd/bashrc.local` | interactive bash additions |
| `~/.config/git/user.conf` | git identity and signing key |
| `~/.config/mise/miserc.local.toml` | module selection (gitignored inside `mise-config/`) |
| `.devcontainer/.env` | Compose value `PASSWORD`, and `TUNNEL_TOKEN` if you use the optional tunnel in `compose.yaml`. A value exported in your shell wins over this file, so a stray `PASSWORD` in the environment becomes the RDP password. A devcontainer mounts the whole checkout, so an agent inside it can read this file. Put nothing else in it, and no GitHub or other tokens |
| `~/.config/djd/age.txt` | age identity that decrypts the secrets module |

## age-encrypted secrets

`mise-config/config.secrets.toml` is the one place where secret values are committed, and only as age ciphertext written by `djd secret set`.

- The identity lives at `~/.config/djd/age.txt` (mode 600), outside the checkout. `age.txt` is ignored by git and Docker anyway, because mise's default key path `~/.config/mise/age.txt` is this repo's `mise-config/`.
- Ciphertext in a public repo is safe only while the key is. Keep the key off machines that run untrusted code. Back it up offline, because losing every copy loses the values.
- Select the `secrets` module only on machines you own. Every process there sees the decrypted values, agents included. The Docker images never select it.
- Rotating a key means re-running `djd secret set` for each value on a machine that holds the new key.
- mise expands `$VAR` and `{{ }}` in a value after it decrypts it, so a secret that contains `$` or `{{` comes back changed. Do not store such a value.
- An empty answer at the `djd secret set` prompt replaces an existing value with an empty one.
- `djd secret set` is a raw mise task, so it can read its prompt once the module holds values ([why](docs/problems.md#secrets)). A value that an older `djd` stored on a machine with the module selected can be empty, because an empty value decrypts and `djd doctor` accepts it. Set it again.
- `age.strict` is off on purpose: with it on, a machine without the key fails every mise command and cannot recover itself. With it off, a missing, wrong or unreadable key leaves the variables unset without a message, so `djd doctor` runs `mise env` with strict on and fails when the key is missing, wrong, unreadable or accessible to group or others. [Architecture](docs/architecture.md#secrets-use-the-age-support-of-mise) has the details.

## GitHub tokens

- Tool installs read public releases. A token only lifts the anonymous rate limit and needs no scope. Use a classic token with no scopes or a fine-grained token with no permissions. Do not use `gh auth token`: it hands the install step, which runs third-party tooling, every scope your login has. `mise-config/config.toml` sets `github.gh_cli_tokens = false`, so mise does not read the token that `gh auth login` stores. It sends only the token in `MISE_GITHUB_TOKEN` (or `GITHUB_TOKEN`).
- `mise run build`, `test`, `test:desktop` and `ci` never fall back to `gh auth token`. They stop with a message unless `GITHUB_TOKEN` is set (`test` and `test:desktop` build first). `GITHUB_TOKEN=` (empty) builds anonymously. `mise run up` and the devcontainer do not check the variable, and build anonymously when it is unset.
- Workflows run with `contents: read`, and `push.yaml` and `tag.yaml` declare `permissions: {}` at the top, so each job states its own grant. `GITHUB_TOKEN` goes to the steps that need it, not to the whole job. The checkout, metadata and build actions also receive `github.token` by default, and `full-weekly.yaml` passes it as `MISE_GITHUB_TOKEN` to `djd update`. The `lint` job installs from `.mise/mise.lock` (`MISE_LOCKED`) and sets no token for its steps. Only `jdx/mise-action` receives `github.token`, through its `github_token` input, for its own step that installs mise. Only `tag.yaml` (`contents: write`, `actions: write`, `checks: read`) and `push.yaml` (`packages: write`) can write, and `tag.yaml` accepts only successful push runs of this repository's `main`.
- The release build passes the `packages: write` token to the tools layer only, as a BuildKit secret, so code that an upstream tool runs while installing could read it. That code could push over `ghcr.io/dayjobdoor/dotfiles:latest`, which agent sandboxes pull. A scope-less token stored as a repository secret and passed to the build instead of `GITHUB_TOKEN` would remove this. That change is not applied. It is a recommendation, and it costs one token to create and rotate. The job token would stay with the registry login.
- The apt layer builds in a separate `RUN` without the secret, so the maintainer scripts of apt packages, which run as root and include Brave's deb, never see it. A throwaway Dockerfile that printed the token count in both layers showed 0 and 1.
- `minimum_release_age = "3d"` in `mise-config/config.toml` delays brand-new releases of mise tools only. The exception is `pi` and `omp` ([tech.md](docs/tech.md#modules) gives the setting and the reason). They install on the day they ship, and they run with your full rights in every agent sandbox. apt packages, Brave included, get no delay.
- A token stored with `djd secret set GITHUB_TOKEN` is visible to every process on that machine. Store a read-only one.

## Workflows and releases

- `push.yaml` smoke-tests every pushed image by digest before `merge` moves a tag. It runs `djd doctor` in the `latest` image on each architecture, and a red smoke blocks every floating tag. The pushed images are rebuilt, not the ones that `mise run test` checked, and `latest` tools and unpinned apt packages can make their bytes differ. This step is the only test of the pushed bytes. No build cache enters the release, because the builds set no `cache-from` or `cache-to`. Both buildx setups set `cache-binary: false`, which only keeps a pinned buildx binary out of the Actions cache.
- `tag.yaml` creates the release first, then dispatches `push.yaml` for the new tag and waits for that run. It fails when the publish fails, so a failed publish notifies the person whose push produced the release. Re-running `tag.yaml` does not retry the publish ([how to retry](docs/guidance.md#retry-a-failed-publish)). A re-run of CI for a commit that already has a release does not dispatch a publish, so a released tag is not rebuilt by accident.
- [docs/maintenance.md](docs/maintenance.md#release-chain) records the releases that went through the wait and the smoke test. `push.yaml` also refuses a tag whose commit is not on `main`, using the compare API, so a tag push alone cannot publish an unreviewed commit.
- GitHub disables scheduled workflows in a public repository after 60 days without activity, and the weekly runs then stop without a message ([docs/maintenance.md](docs/maintenance.md#workflows) says how to re-enable them).
- `docs.yaml` runs `mise run lint:docs` and, in a second job, `mise run lint:secrets` (gitleaks over the history, with `MISE_LOCKED` and no token). Both have a read-only token. They run on pushes and pull requests that change Markdown, `docs/` or `llms.txt`, except the Markdown under `home/.config/pi/**` and `home/.config/omp/**`, which `ci.yaml` covers. The workflow never releases, because `tag.yaml` listens to `CI` alone.

The repository settings below are recommendations. Nothing in the repository enforces them, and they were not applied. When checked with `gh api` on 2026-11-08 (check again before relying on it), the repository had no rulesets, `main` was not protected, and no release was immutable. The endpoint for the default workflow token permission answered 403, so that setting is unknown. [docs/guidance.md](docs/guidance.md#harden-the-repository-settings) lists the steps.

- A tag ruleset on `refs/tags/[0-9]*` that blocks update and deletion. It must not block creation, because `tag.yaml` pushes the tag; `push.yaml` itself refuses a tagged commit that is not on `main`.
- No force-push and no deletion on `main`.
- "Require actions to be pinned to a full-length commit SHA", and immutable releases.
- A read-only default workflow token.

## Docker

- Tokens enter builds only through a BuildKit secret (`--secret id=github_token,env=GITHUB_TOKEN`), mounted as `MISE_GITHUB_TOKEN` for the tools layer alone, not for the apt layer, which also runs the final hook. Never pass tokens through `ARG` or `ENV`, because both persist in image metadata. A scan of the final images for the token value found nothing.
- The image runs as the `dayjobdoor` user, not root. That user has passwordless sudo because the container is the isolation boundary. The desktop container runs xrdp as root (`user: root` in `.devcontainer/compose.yaml`).
- The image takes its RDP password at container start, never at build time. `compose.yaml` passes it as the `djd_rdp_password` secret (from `PASSWORD` in `.devcontainer/.env`), mounted at `/run/secrets/djd_rdp_password`, so it is in neither `docker inspect` nor `/proc/1/cmdline`. Only a password given to the entrypoint as an argument, as `test:desktop` does for its throwaway containers, shows in both. A process that runs as root in the container, including the `dayjobdoor` user through passwordless sudo, can still read the secret file. Keep `.devcontainer/.env` at mode 600, and single-quote a `PASSWORD` that contains a `$`. The entrypoint refuses a password with a newline (exit 2), because `chpasswd` would take the second line as another account's password.
- The optional Cloudflare tunnel in `compose.yaml` (commented out) takes `TUNNEL_TOKEN` through `environment`, not on the command line, so `ps` on the host does not show it. `docker inspect` still does.
- Compose publishes RDP on `127.0.0.1` (`ports` in `compose.yaml`). The image itself does not restrict where the port is published.

## Warp module

- `cloudflare-warp` comes from `https://pkg.cloudflareclient.com`, declared in `config.warp.toml` with suite `resolute` and one pinned key fingerprint. The fingerprint is read from the same `pubkey.gpg` that mise downloads, and Cloudflare publishes no second place to compare it with, so it is trust on first use: it stops a later key swap, not a wrong first key. The key has no expiry date.
- The package runs `warp-svc` as root, and a connected client takes over the routes and the DNS of the machine. The module is for VMs and real hosts; the Docker image does not carry it. `djd module add warp` does not register or connect: that is a manual `warp-cli registration new`, which creates a device on Cloudflare's side (`warp-cli registration delete` removes it).

## Server module

- SSH accepts keys only (`/etc/ssh/sshd_config.d/10-djd.conf` sets no passwords, no keyboard-interactive and no root login). Install your public key before you select `server` on a machine you reach over password SSH. The `post-packages` hook refuses the apply, before the drop-in is written, when `~/.ssh/authorized_keys` holds no key, when the apply runs as root, or when sshd listens on a port other than 22 (the firewall rule opens 22 only); `DJD_SKIP_SSH_CHECKS=1` skips that for a machine you reach by a console, `incus exec` or `multipass exec`.
- The hook `sshd-keys-only` runs on each `djd apply` and in `djd doctor`. It fails when another setting overrides the drop-in, for example an earlier-sorting drop-in with `PasswordAuthentication yes`. A real sshd accepted that password login in a test, so the guard covers a real case.
- A `Match` block defeats "the first value wins". The hook evaluates `sshd -T -C` for the current user when a `Match` line exists, so it catches `Match all` and `Match User <current user>` that re-enable passwords. A `Match` for another user or an address, or in a file outside `sshd_config` and `sshd_config.d`, passes the hook ([scope](docs/problems.md#sshd-match-blocks-are-only-partly-covered)).
- ufw denies incoming by default, rate-limits 22/tcp, and opens RDP (3389/tcp) only to private networks (10/8, 172.16/12, 192.168/16, and IPv6 fc00::/7 and fe80::/10). Reach RDP from anywhere else through `ssh -L 33389:localhost:3389 <host>`.
- `/etc/docker/daemon.json` binds published container ports to `127.0.0.1` when `-p` names no address, because Docker's port rules bypass ufw. Publish to the network on purpose with `-p 0.0.0.0:8080:80`. Networks created before the module was applied keep their old default.
- `djd module remove server` brings back password logins and published ports on every address, and the command prints a warning. The firewall stays enabled ([details](docs/tech.md#modules)).
- `djd module add` warns when `secrets` and `agent` are both selected, because every agent tool on the machine would see the decrypted values. It does not refuse, since a personal workstation may want both; keep the combination off sandboxes.

## The desktop

- xrdp listens on 3389/tcp on every interface of every machine, because the desktop is part of the base. The `desktop-final` hook sets `security_layer=tls` and `AllowRootLogin=false`, drops the generic proxy sessions `vnc-any` and `neutrinordp-any` from `xrdp.ini`, and restarts xrdp once per change unless an RDP session is open. The image test checks that `/sec:rdp` and a root login are refused. mstsc and Windows App were not tried against `tls`. [Architecture](docs/architecture.md#the-rdp-service-is-tls-only-and-keeps-the-other-xrdp-defaults) explains the settings.
- The TLS key is made per container. The image keeps the build-time snakeoil key (CN=localhost, valid for ten years) in its layers, so anyone who pulls the image holds it, but nothing uses it: the entrypoint generates a new pair before xrdp starts, and the image test requires different fingerprints in two containers. A VM has its own pair from its own `ssl-cert` install.
- The firewall rules for RDP belong to the server module. A machine without `server` has no firewall rule for xrdp, so keep it off untrusted networks. `djd module add` prints a warning whenever `server` is not selected. A cloud image's user has a locked password, so nobody can log in over RDP until you set one, which limits the exposure but does not remove it.
- Four apps are required (ghostty, Brave, Zed and Zen), and none installs through `curl | sh`. [Architecture](docs/architecture.md#the-desktop-apps-each-carry-a-trust-anchor) lists what proves each download. Two limits follow from it. Brave's repository metadata has no `Valid-Until`, so anyone who can answer for its CDN can replay old, validly signed metadata and hold a machine on an older Brave, while forging a package would need the pinned keys. A compromised Zed or Zen release would pass the digest check, because Zen publishes no signature or attestation and mise does not require Zed's. The 3-day `minimum_release_age` is the only delay.
- The Docker image runs Brave with `--no-sandbox`, which also switches off the renderer's seccomp-bpf sandbox. The image user has passwordless sudo, so a renderer bug gives root inside the container at once. `compose.yaml` mounts no volumes, so that root sees the container and not your checkout, but a devcontainer does mount the checkout, so do not browse in one. Leaving the container still needs a kernel or runtime bug. Treat the browser in that image as a convenience and use a VM for untrusted sites. The reasons and the untried alternative are in Architecture.
- Obsidian and Ferdium (Electron) keep Chromium's sandbox in a VM. Ubuntu's AppArmor denies user namespaces to a program with no profile, so `/etc/apparmor.d/djd-electron` names those two programs under `~/.local/share/mise/installs` and allows only `userns` for them (`flags=(unconfined)` changes nothing else). The profile is user-writable territory: anyone who can write that path runs a program with user namespaces, which is a small step past what that user could do anyway. In the Docker image they run with `--no-sandbox`, like Brave. The pin of Obsidian and Ferdium covers only the first launch: Obsidian checks GitHub for updates at start (its log says so) and can load a newer app package from `~/.config/obsidian` instead of the pinned one, and Ferdium ships `resources/app-update.yml` for electron-updater. Nothing here switches either updater off, unlike Zen's `policies.json`; turn off Obsidian's automatic updates in its settings if the pin should hold. Wireshark's `dumpcap` captures for the group `wireshark` (the debconf answer `install-setuid`), and the desktop user joins it, so that user can capture all traffic of the machine without root.
- Zed and Zen could update themselves in place, without mise's digest check and without the release age. The base disables both updaters ([how](docs/architecture.md#the-desktop-apps-each-carry-a-trust-anchor)). Zed's telemetry and `auto_update` are off in `home/.config/zed/settings.json`, but whether Zed then sends nothing was not observed.
- mise puts a tool's own bin directories ahead of `PATH` while a `postinstall` runs. The six scripts (Zed, Zen, HackGen NF, Obsidian, Vicinae and Ferdium) reset `PATH` to `/usr/bin:/bin`, so a poisoned tarball cannot shadow `sed` or `install` during the release build (shown with a fake `bin/sed`, not with a real poisoned release). The HackGen NF font is a pinned `http:hackgen` tool, and a wrong checksum fails the install.
- Audio over RDP adds no listening port. `pipewire-pulse` listens on a unix socket in the `0700` runtime directory, and its `tcp:4713` entry is commented out, so the ufw rules need no change.

### Known limits of the RDP service

These limits are known and the module does not change them. [docs/problems.md](docs/problems.md#rdp-security-and-known-limits) holds the probe results and the switch for each channel. A user with a long random `PASSWORD`, the loopback binding and a VM for untrusted work covers most of this.

- **Clipboard.** It is open in both directions. Any process in the session can read what you copy, a password manager entry included, or replace it to plant a command that you paste into your own terminal.
- **No lockout across connections.** A new connection resets the retry counter, and `pam_faillock` and fail2ban are absent. Password strength and the loopback binding are the only defenses. The user has passwordless sudo, so one guessed password is root in the container.
- **TLS 1.2 suites.** Static-RSA and CBC suites are still accepted, so an active attacker on the path gets weaker suites than a modern client needs. `tls_ciphers` is not set; the tested remedy is in [problems.md](docs/problems.md#limits-and-exposure).
- **New certificate at every container start.** Verification by name always fails and a pinned fingerprint changes with each start. FreeRDP's "host key has changed" on the first connect is its message, not a change.
- **`security_layer=hybrid` is not valid.** xrdp silently falls back to `negotiate`, which re-opens the RDP layer. Only `tls` is right here, and `djd doctor` checks for it.
- **No NLA.** This xrdp offers no CredSSP, so `/sec:nla` is refused.
- **Drives, printers, microphone.** None of these channels is switched off. [problems.md](docs/problems.md#channels) lists the switch for each.

## Checks

- `.githooks/pre-commit` runs gitleaks on staged changes through mise. Enable it once per clone with `git config core.hooksPath .githooks`. It needs mise and a trusted checkout. Run `mise trust` in the clone, or work in `~/.dotfiles`, which `trusted_config_paths` already trusts. Without that every commit fails.
- `mise run lint` (the CI `lint` job) scans the whole git history with gitleaks, or the files when there is no git directory, and audits the workflows with jactionlint (rules such as `artipacked` for a persisted token, `dangerous-triggers`, `cache-poisoning`, and `unpinned-uses`; `jactionlint --list-rules` lists them all).
- Repo tools install from `.mise/mise.lock`, which pins each version and its checksum. Dependabot proposes updates to the pinned action SHAs.
- The zsh plugins are `[plugins.<name>]` entries in `home/.config/sheldon/plugins.toml`, each pinned to a commit with `rev`, so a new machine does not run whatever a default branch holds that day. sheldon checks out the submodules at the commit that a plugin pins (zsh-abbr's zsh-job-queue). `hooks/sheldon-lock` fetches them on every apply, and `djd doctor` reports a missing lock or plugin directory. No check requires a `rev` on a new entry, so update a pin on purpose. fast-syntax-highlighting downloads one theme file with `curl` the first time a deferred plugin load runs.
- `mise run ci` gives act a copy of tracked and unignored files only (`tests/tree.sh`). act's `.secrets` and `.vars` files are gitignored and dockerignored.
- Release images are built without a build cache.

## If a secret leaks

1. Rotate or revoke it first. A pushed secret is compromised even if the commit is removed.
2. Then purge it from history (`git filter-repo`) and force-push.
