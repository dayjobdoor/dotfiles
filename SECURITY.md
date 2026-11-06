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

`.gitignore` and `.dockerignore` cover the common file names. The checks below catch the rest.

## Local overrides

All of these are outside the repo or gitignored. The shell and git files are read when present.

| File | Purpose |
| --- | --- |
| `~/.config/djd/profile.local` | extra environment, loaded at the end of `~/.profile`. Every zsh, login bash and interactive bash reads it; `sh -c` and a non-login, non-interactive `bash -c` do not. A value here does not reach shimmed tools when the same name is set in a module's `[env]`, because mise's `[env]` wins (use `config.local.toml` for those) |
| `~/.config/mise/config.local.toml` | overrides the `[env]` values and settings of the modules, for example `NPM_CONFIG_CACHE` or `DO_NOT_TRACK`. The file sits in `mise-config/`, and `*.local.toml` is gitignored and dockerignored |
| `~/.config/zsh/.zshrc.local` | interactive zsh additions |
| `~/.config/djd/bashrc.local` | interactive bash additions |
| `~/.config/git/user.conf` | git identity and signing key |
| `~/.config/mise/miserc.local.toml` | module selection (gitignored inside `mise-config/`) |
| `.devcontainer/.env` | Compose values `PASSWORD` and `RDP_PORT`, and `TUNNEL_TOKEN` if you use the optional tunnel in `compose.yaml`. A value exported in your shell wins over this file, so a stray `PASSWORD` or `RDP_PORT` in the environment becomes the RDP password or port. A devcontainer mounts the whole checkout, so an agent inside it can read this file. Put nothing else in it, and no GitHub or other tokens |
| `~/.config/djd/age.txt` | age identity that decrypts the secrets module |

## age-encrypted secrets

`mise-config/config.secrets.toml` is the one place where secret values are committed, and only as age ciphertext written by `djd secret set`.

- The identity lives at `~/.config/djd/age.txt` (mode 600), outside the checkout. `age.txt` is ignored by git and Docker anyway, because mise's default key path `~/.config/mise/age.txt` is this repo's `mise-config/`.
- Ciphertext in a public repo is safe only while the key is. Keep the key off machines that run untrusted code. Back it up offline, because losing every copy loses the values.
- Select the `secrets` module only on machines you own. Every process there sees the decrypted values, agents included. The Docker images never select it.
- Rotating a key means re-running `djd secret set` for each value on a machine that holds the new key.
- mise expands `$VAR` and `{{ }}` in a value after it decrypts it. A secret that contains `$` or `{{` comes back changed (observed with `pw$HOME-and-${USER}-end`, which became `pw/home/ubuntu-and-${USER}-end`). Do not store such a value. No setting that turns the expansion off was found.
- An empty answer at the `djd secret set` prompt replaces an existing value with an empty one.
- `djd secret set` is a raw mise task (`#MISE raw=true`). Without that, mise stopped passing stdin to the task once the secrets module was selected and held a value. The second and later `set` then stored an empty ciphertext, exited 0, and `djd doctor` still said `ok`, because an empty value decrypts. This was reproduced and fixed. A value stored by an older `djd` on a machine with the module selected can be empty, so set it again.
- `age.strict` is off on purpose. With it on, a machine that selected the module and has no key fails every mise command, including `djd doctor`, `djd module remove secrets`, `mise bootstrap status` and the shims, so the recovery path is gone (observed). With it off, a missing, wrong or unreadable key leaves the variables unset without a message, and a corrupt payload is skipped silently. `djd doctor` compensates. It runs `mise env` with strict on, and fails when the key is missing, wrong, unreadable, or accessible to group or others (mode 0600 or 0400 pass).

## GitHub tokens

- Tool installs read public releases. A token only lifts the anonymous rate limit and needs no scope. Use a classic token with no scopes or a fine-grained token with no permissions. `gh auth token` also works, but it hands the install step, which runs third-party tooling, every scope your login has. mise reads the token that `gh auth login` stores, because `github.gh_cli_tokens` is on by default, so a machine with a logged-in `gh` already sends that token on installs.
- `mise run build`, `test`, `test:desktop` and `ci` no longer fall back to `gh auth token`. They stop with a message unless `GITHUB_TOKEN` is set. `GITHUB_TOKEN=` (empty) builds anonymously.
- Workflows run with `contents: read`, and `push.yaml` and `tag.yaml` declare `permissions: {}` at the top, so each job states its own grant. `GITHUB_TOKEN` goes to the steps that need it, not to the whole job. The checkout, metadata and build actions also receive `github.token` by default, and `full-weekly.yaml` passes it as `MISE_GITHUB_TOKEN` to `djd update`. `lint` and `agentos` install from `mise.lock` (`MISE_LOCKED`) and pass no token to their steps (`jdx/mise-action` has its own `github_token` input, which defaults to `github.token` for its own step). Only `tag.yaml` (`contents: write`, `actions: write`, `checks: read`) and `push.yaml` (`packages: write`) can write, and `tag.yaml` accepts only successful push runs of this repository's `main`.
- The release build passes the `packages: write` token to the tools layer only, as a BuildKit secret, so code that an upstream tool runs while installing could read it. That code could push over `ghcr.io/dayjobdoor/dotfiles:{latest,sandbox,desktop}`, which agent sandboxes pull. A scope-less token stored as a repository secret and passed to the build instead of `GITHUB_TOKEN` would remove this. That change is not applied. It is a recommendation, and it costs one token to create and rotate. The job token would stay with the registry login.
- The apt layer builds in a separate `RUN` without the secret, so the maintainer scripts of apt packages, which run as root and include Brave's deb, never see it. A throwaway Dockerfile that printed the token count in both layers showed 0 and 1.
- `minimum_release_age = "3d"` in `mise-config/config.toml` delays brand-new releases of mise tools only. The exception is `pi` and `omp` (`minimum_release_age_excludes` in `config.agent.toml`). They install on the day they ship, because they release often and the owner wants new releases at once, and they run with your full rights in every agent sandbox. apt packages, Brave included, get no delay.
- A token stored with `djd secret set GITHUB_TOKEN` is visible to every process on that machine. Store a read-only one.

## Workflows and releases

- `push.yaml` smoke-tests every pushed image by digest before `merge` moves a tag. It runs `djd doctor` in each flavor on each architecture, and a red smoke blocks every floating tag. The pushed images are rebuilt, not the ones that `mise run test` checked, and `latest` tools and unpinned apt packages can make their bytes differ. This step is the only test of the pushed bytes. No build cache enters the release, because the builds set no `cache-from` or `cache-to`. Both buildx setups set `cache-binary: false`, which only keeps a pinned buildx binary out of the Actions cache.
- `tag.yaml` creates the release first, then dispatches `push.yaml` for the new tag and waits for that run. It fails when the publish fails, so a failed publish notifies the person whose push produced the release. Re-running `tag.yaml` does not retry the publish. Run `gh workflow run push.yaml --ref X.Y.Z` instead, as [docs/how-to.md](docs/how-to.md#retry-a-failed-publish) says. A re-run of CI for a commit that already has a release does not dispatch a publish, so a released tag is not rebuilt by accident.
- The wait and the smoke test have run on GitHub (release 0.0.6, 5 November 2026). `push.yaml` also refuses a tag whose commit is not on `main`, using the compare API, so a tag push alone cannot publish an unreviewed commit.
- GitHub disables scheduled workflows after 60 days with no repository activity in a public repository. The weekly CI run and `full-weekly` then stop without a message. Re-enable them in the Actions tab.
- `docs.yaml` runs only `mise run lint:docs`, with a read-only token, on pushes and pull requests that change Markdown, `docs/` or `llms.txt`, except `agent/**`. It never releases, because `tag.yaml` listens to `CI` alone.

The repository settings below are recommendations. Nothing in the repository enforces them, and they were not applied. When checked with `gh api` on 2026-11-01, the repository had no rulesets, `main` was not protected, and no release was immutable. The endpoint for the default workflow token permission answered 403, so that setting is unknown. [docs/how-to.md](docs/how-to.md#harden-the-repository-settings) lists the steps.

- A tag ruleset on `refs/tags/[0-9]*` that blocks update and deletion. It must not block creation, because `tag.yaml` pushes the tag; `push.yaml` itself refuses a tagged commit that is not on `main`.
- No force-push and no deletion on `main`.
- "Require actions to be pinned to a full-length commit SHA", and immutable releases.
- A read-only default workflow token.

## Docker

- Tokens enter builds only through a BuildKit secret (`--secret id=github_token,env=GITHUB_TOKEN`), mounted as `MISE_GITHUB_TOKEN` for the tools layer alone, not for the apt layer, which also runs the final hook. Never pass tokens through `ARG` or `ENV`, because both persist in image metadata. A scan of the final images for the token value found nothing.
- The sandbox image runs as the `ubuntu` user, not root. That user has passwordless sudo because the container is the isolation boundary. The desktop image runs xrdp as root (`user: root` in `.devcontainer/compose.yaml`).
- The desktop image takes its RDP password at container start, never at build time. `compose.yaml` passes it as the `djd_rdp_password` secret (from `PASSWORD` in `.devcontainer/.env`), mounted at `/run/secrets/djd_rdp_password`, so it is in neither `docker inspect` nor `/proc/1/cmdline`. Only a password given to the entrypoint as an argument, as `test:desktop` does for its throwaway containers, shows in both. A process that runs as root in the container, including the `ubuntu` user through passwordless sudo, can still read the secret file. Keep `.devcontainer/.env` at mode 600, and single-quote a `PASSWORD` that contains a `$`.
- The optional Cloudflare tunnel in `compose.yaml` (commented out) takes `TUNNEL_TOKEN` through `environment`, not on the command line, so `ps` on the host does not show it. `docker inspect` still does.
- Compose publishes RDP on `127.0.0.1` (`ports` in `compose.yaml`). The image itself does not restrict where the port is published.

## Server module

- SSH accepts keys only (`/etc/ssh/sshd_config.d/10-djd.conf` sets no passwords, no keyboard-interactive and no root login). Install your public key before you select `server` on a machine you reach over password SSH. The `post-packages` hook refuses the apply, before the drop-in is written, when `~/.ssh/authorized_keys` holds no key, when the apply runs as root, or when sshd listens on a port other than 22 (the firewall rule opens 22 only); `DJD_SKIP_SSH_CHECKS=1` skips that for a machine you reach by a console, `incus exec` or `multipass exec`.
- The hook `sshd-keys-only` runs on each `djd apply` and in `djd doctor`. It fails when another setting overrides the drop-in, for example an earlier-sorting drop-in with `PasswordAuthentication yes`. A real sshd accepted that password login in a test, so the guard covers a real case.
- A `Match` block defeats "the first value wins". When any `Match` line exists in `sshd_config` or `sshd_config.d`, the hook evaluates `sshd -T -C user=<current user>,host=localhost,addr=203.0.113.1`. It catches `Match all` and `Match User <current user>` that re-enable passwords. It cannot see a `Match` for another user or an address, nor a `Match` in a file outside those two paths. Those cases pass the hook.
- ufw denies incoming by default, rate-limits 22/tcp, and opens RDP (3389/tcp) only to private networks (10/8, 172.16/12, 192.168/16, and IPv6 fc00::/7 and fe80::/10). Reach RDP from anywhere else through `ssh -L 33389:localhost:3389 <host>`.
- `/etc/docker/daemon.json` binds published container ports to `127.0.0.1` when `-p` names no address, because Docker's port rules bypass ufw. Publish to the network on purpose with `-p 0.0.0.0:8080:80`. Networks created before the module was applied keep their old default.
- `djd module remove server` deletes the sshd drop-in and `daemon.json`, so password logins and published ports on every address return. The firewall stays enabled with its rules, SSH included, and the command prints a warning.
- `djd module add` warns when `secrets` and `agent` are both selected, because every agent tool on the machine would see the decrypted values. It does not refuse, since a personal workstation may want both; keep the combination off sandboxes.

## Desktop module

- xrdp listens on 3389/tcp on every interface. The `desktop-final` hook sets `security_layer=tls` in `/etc/xrdp/xrdp.ini`, so a client cannot fall back to the RDP security layer, and `AllowRootLogin=false` in `sesman.ini`. A running xrdp keeps the values it started with, so the hook restarts it once per change, unless an RDP session is open: it then prints the restart command and the next apply tries again.
- The image test shows that `xfreerdp3 /sec:rdp` is refused, and that a second server with `security_layer=negotiate` keeps the same client connected, so the refusal comes from the setting. It also shows that a root login is refused where a control with `AllowRootLogin=true` starts a root session. mstsc and Windows App were not tried against `tls`. Ubuntu locks the root password by default as well.
- The TLS key is made per container. The `ssl-cert` package made one snakeoil pair while the desktop image was built, and xrdp reads it through `/etc/xrdp/cert.pem` and `key.pem`. Every container of the published image would have presented the same certificate, and anyone who pulls the image holds its private key (on the published `desktop` tag, `cert.pem` was the snakeoil certificate made at build time, CN=localhost, valid for ten years). The entrypoint now runs `make-ssl-cert generate-default-snakeoil --force-overwrite` before it starts xrdp. The image test requires that two containers present different fingerprints, both different from the build-time one. The build-time key stays in the published layers and is public, but nothing uses it. A VM has its own pair from its own `ssl-cert` install.
- The firewall rules for RDP belong to the server module. A machine with `desktop` and without `server` has no firewall rule, so keep it off untrusted networks. `djd module add desktop` prints a warning in that case.
- Four apps are required (ghostty, Brave, Zed and Zen), and none installs through `curl | sh`. ghostty comes from the signed Ubuntu archive. Brave comes from its apt repository, and `config.desktop.toml` pins the three signing-key fingerprints that brave.com/signing-keys lists. mise keeps only those keys, embeds them in the source's `Signed-By`, and fails the apply when one is missing or has changed (tested once with a changed fingerprint). The repository's metadata has no `Valid-Until`, so anyone who can answer for its CDN can replay old, validly signed metadata and hold a machine on an older Brave. Forging a package would need the pinned keys.
- Zed comes from a GitHub release. mise checks the digest of every download, and the GitHub artifact attestation when the release has one, but it does not require one. A release uploaded with a stolen maintainer token carries none and passes like a Zen release. Zen publishes neither a signature nor an attestation, so mise can verify only the digest that GitHub reports. A compromised Zed or Zen release would pass those checks, and the 3-day `minimum_release_age` is the only delay.
- The HackGen NF font is the mise tool `http:hackgen` in `config.desktop.toml`. mise downloads the zip and checks its pinned sha256, and a wrong checksum fails the install (tested). The `desktop-final` hook no longer downloads anything. The postinstall copies the `.ttf` files to `~/.local/share/fonts/HackGen`.
- The desktop Docker image runs Brave with `--no-sandbox`, because Docker's default seccomp policy blocks the namespaces Brave's sandbox needs and Brave aborts without them (tested on OrbStack in November 2026). The flag also switches off the renderer's seccomp-bpf sandbox. The image user has passwordless sudo, so a renderer bug gives root inside the container at once. `compose.yaml` gives the desktop service no volumes, so that root sees the container and not your checkout. A devcontainer does mount the checkout, so do not browse in one. Leaving the container still needs a kernel or runtime bug. Zen logged that it could not create a user namespace there and still ran, so its sandbox is probably weaker too. The Dockerfile adds the flag to a user-level copy of the menu entry. The module does not, so a VM keeps Brave's sandbox. A seccomp profile that allows user namespaces would keep Brave's sandbox on without `SYS_ADMIN`. It is the alternative to `--no-sandbox`, it widens the kernel surface of everything in the container, and it is neither shipped nor tried. Treat the browser in that image as a convenience and use a VM for untrusted sites.
- Zed and Zen could update themselves in place, without mise's digest check and without the release age. The module sets `ZED_UPDATE_EXPLANATION`, which makes Zed skip its update poll (read in Zed's source, not run), and the Zen `postinstall` writes `distribution/policies.json` with `DisableAppUpdate` and `DisableTelemetry`. Zen's `about:policies` lists both as active, and no updater was run. Updates go through `mise upgrade`. The dotfile `desktop/.config/zed/settings.json` turns Zed's telemetry (`diagnostics`, `metrics`) and `auto_update` off. The keys come from Zed's default settings, and Zed still opens its window with the file in place. Whether Zed then sends nothing was not observed. Zed may rewrite the file through its symlink.
- mise puts a tool's own bin directories ahead of `PATH` while a `postinstall` runs. The three scripts (Zed, Zen and HackGen NF) reset `PATH` to `/usr/bin:/bin`, so a poisoned tarball cannot shadow `sed` or `install` during the release build (shown with a fake `bin/sed`, not with a real poisoned release).
- Audio over RDP adds no listening port. `pipewire-pulse` listens on a unix socket in the `0700` runtime directory of the user, and its shipped `tcp:4713` entry is commented out (checked in a throwaway container), so the ufw rules need no change. The microphone and drive channels are in the table below.

### Known limits of the RDP service

These limits are known and the module does not change them. They were probed on 2026-11-01 against the desktop image (xrdp 0.10.1 on Ubuntu 26.04, with FreeRDP 3.32.1 as the client, both in containers). [docs/reference.md](docs/reference.md#rdp-security-and-known-limits) holds the probe results. A user with a long random `PASSWORD`, the loopback binding and a VM for untrusted work covers most of this.

| Limit | What was observed | What it means |
| --- | --- | --- |
| Clipboard | Open in both directions by default, and xrdp logs nothing. | Any process in the session can read what you copy on your machine, a password manager entry included. It can also replace your clipboard, for example to plant a command that you paste into your own terminal. |
| No lockout across connections | `MaxLoginRetry=4` ends one connection after the fifth failed try, and a new connection resets the counter. Six wrong passwords on six connections, then the right one, logged in. `pam_faillock` and fail2ban are absent. The `tsusers` group does not exist and `AlwaysGroupCheck=false`, so every account may log in. Only the roughly 2 s `pam_unix` delay slows a guess. | Password strength and the loopback binding are the only defenses. Parallel connections would multiply the guess rate (inference, not run). The user has passwordless sudo, so one guessed password is root in the container. Failed logins appear as `AUTHFAIL` lines in `/var/log/xrdp-sesman.log` only. |
| TLS 1.2 suites | `ssl_protocols=TLSv1.2, TLSv1.3`, and TLS 1.0 and 1.1 are refused. TLS 1.2 still accepts static-RSA (`AES256-GCM-SHA384`, no forward secrecy) and CBC suites (`AES128-SHA`, `ECDHE-RSA-AES256-SHA384`). `tls_ciphers` is commented out in `xrdp.ini`. | An active attacker on the path gets weaker suites than a modern client needs. `tls_ciphers=ECDHE+AESGCM:ECDHE+CHACHA20` refused all three in a throwaway container and a full FreeRDP connect still worked. It is not applied. RC4 and 3DES were not exercised. |
| New certificate at every container start | The entrypoint makes a self-signed RSA 2048 certificate (ten years) at each start. Its CN and SAN are the container hostname, which is the container ID by default, so the name never matches what a client types. | A client that trusts on first use warns that the certificate changed after every restart, and `restart: unless-stopped` restarts the container with the Docker daemon or the host. Verification by name always fails, and a pinned fingerprint changes with each start. FreeRDP also prints "host key has changed" on the very first connect when the name mismatches. That is its message, not a change. |
| `security_layer=hybrid` is not valid | xrdp logs that it does not recognize the value and uses `negotiate`. The log then shows `configured [SSL\|RDP]`. | A typo or an "upgrade" to `hybrid` silently re-enables the RDP security layer. Only `tls` is right here, and `djd doctor` checks for it. `negotiate` also re-opens the RDP layer. |
| No NLA | This xrdp offers no CredSSP, and `sesman.ini` has no credential backend setting. A client that insists on NLA (`/sec:nla`) is refused. | Network level authentication does not exist as an option. mstsc and Windows App were not tried, and the inference is that they take TLS like FreeRDP's default. |

Channels, with the switch for each (all switches tested in a throwaway container and none applied).

| Channel | Default | Observed | Switch |
| --- | --- | --- | --- |
| Clipboard (`cliprdr`) | on | Works both ways. | `RestrictInboundClipboard=all` and `RestrictOutboundClipboard=all` in `sesman.ini`, or `cliprdr=false` in `xrdp.ini` |
| Drives and printers (`rdpdr`) | on | `xrdp-chansrv` logs `Detected remote drive`, and nothing mounts. There is no `~/thinclient_drives`. | `rdpdr=false` |
| Playback (`rdpsnd`) | on | `xrdp-sink` is the default sink. | `rdpsnd=false` |
| Microphone (`drdynvc`, `AUDIO_INPUT`) | on | `xrdp-source` exists at every login. `parecord --device=xrdp-source` as the session user worked without any client option and returned only zero bytes. With a client microphone option, the server logs the audio input channel when an app records. Real microphone data was not tested. | The microphone path needs `drdynvc` as well as `rdpsnd`. Leave client microphone redirection off unless you need it. |
| `rail`, `xrdpvr` | on | not tested | `rail=false`, `xrdpvr=false` (untested) |

`sesman.ini` sets `FuseMountName=thinclient_drives` and `FileUmask=077` for mapped drives, which would give every process of the user access to them. The desktop image does have `fuse3` and `libfuse3-4` installed. But `xrdp-chansrv` links no libfuse (`readelf -d`) and holds only the config key names, so no client drive can be mounted, even with `/dev/fuse` granted. A drive test with FreeRDP confirmed that nothing mounts.

## agentOS

- agentOS is in beta, and its security-model page says the review is still going. The boot denies the guest network, because the default policy lets the guest resolve model-provider hosts such as api.anthropic.com. A boot check fetches that host and passes only when curl cannot resolve it. Package downloads run on the host, so the denial costs nothing.
- The bundle is an allowlist of five files. `agentos/boot.mjs` rejects a file that is a symlink or resolves outside the repository (realpath comparison). Nothing from `~`, no key and no token enters it. `tests/agentos-bundle.sh` asserts the exact five files with their paths and content, so an added entry fails CI. Hard links and a file swapped during the export are no longer detected, so the export is not a trust boundary against a hostile working tree. `lint:secrets` scans the files like every tracked file.
- A consumer of `bundle.json` must confine every `path` to `/home/agentos`. In agentOS 0.4.6 a host-side `writeFile` ignores guest permissions (it wrote `/etc/probe` and `/opt/agentos/bin/planted` in a test). The bundle carries no `environment`. A guest `PAGER` is the agentOS default (`less`), and git is covered by `agentos/gitconfig`.
- The registry packages are pinned by sha256 in `agentos/software.lock.json`. `agentos:boot` gives the VM only the locked URLs and digests, and the sidecar rejects any other bytes (a one-character digest change was refused). `bundle.json` carries the same locked `{url, digest}` entries under `software`, so a consumer that passes them on is pinned.
- Nothing compares the live registry with the lock at boot. A registry change cannot fail the boot or CI, and it cannot change what installs. The lock holds what the registry served on the day it was locked. A malicious first lock and an unreviewed `mise run agentos:lock` refresh are not detected, so review the diff. The default bundle of agentos-core (`sh`, coreutils and others) is outside the lock.
- The offline test finds the command of each registry package in the sandbox image, so a command an agent finds in a guest exists there too. Nothing compares the packages with the Ubuntu declarations any more.
- `mise run agentos:boot` starts a native sidecar as the invoking user. Run it in the sandbox image, as AGENTS.md shows.

## Checks

- `.githooks/pre-commit` runs gitleaks on staged changes through mise. Enable it once per clone with `git config core.hooksPath .githooks`. It needs mise and a trusted checkout. Run `mise trust` in the clone, or work in `~/.dotfiles`, which `trusted_config_paths` already trusts. Without that every commit fails.
- `mise run lint` (the CI `lint` job) scans the whole git history with gitleaks, or the files when there is no git directory, and audits the workflows with jactionlint (token persistence, dangerous triggers, cache poisoning, unpinned actions).
- Repo tools install from `mise.lock`, which pins each version and its checksum. Dependabot proposes updates to the pinned action SHAs and to `agentos/package.json`.
- The zsh plugins are `[bootstrap.repos]` entries in `mise-config/config.toml`, each pinned to a commit with `ref`, so a new machine does not run whatever a default branch holds that day. A commit `ref` rules out `depth`, so the clones are full clones. `mise bootstrap status` and `djd doctor` report a missing or drifted checkout. No check requires a `ref` on a new entry, so update a pin on purpose. fast-syntax-highlighting downloads one theme file with `curl` the first time a deferred plugin load runs.
- `mise run ci` gives act a copy of tracked and unignored files only (`tests/tree.sh`). act's `.secrets` and `.vars` files are gitignored and dockerignored.
- Release images are built without a build cache.

## If a secret leaks

1. Rotate or revoke it first. A pushed secret is compromised even if the commit is removed.
2. Then purge it from history (`git filter-repo`) and force-push.
