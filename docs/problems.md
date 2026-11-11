# Problems

Pitfalls, accepted costs and known limits. Each entry says what goes wrong and what the repository does about it. The decisions are in [architecture.md](architecture.md), the lookup tables in [tech.md](tech.md), and the vulnerabilities and hardening in [SECURITY.md](../SECURITY.md).

## Pitfalls

### A program can rewrite a linked file

A program can still change a tracked file through its link. lazygit rewrites its config in place when it migrates renamed keys, and `git config --global` appends to `~/.config/git/config`. Both leave the checkout dirty. A program that saves through a temporary file and a rename, such as `sed -i`, replaces the link with a regular file. `mise dot status` then reports `exists but is not a symlink`, and `djd doctor` fails. `djd apply` moves the new file aside as `*.djd-backup-*` and links the repository file again. [How to keep an edit that a program made](guidance.md#keep-an-edit-that-a-program-made) shows how to save the edit first.

### Herdr's Pi integration only detects tool-spawned nested sessions

The vendored Pi extension is managed by Herdr, so an integration update can overwrite its local fixes. `tests/herdr-state.sh` keeps two behaviors pinned: startup does not wait for a socket response, and a nested Pi launched by an agent shell tool does not report over the parent pane. Pi supplies `PI_SESSION_ID` to that tool environment, which makes this case detectable. Pi does not inject session metadata into user-entered `!` commands, so a nested session launched there needs an upstream Herdr/Pi handoff marker; the local extension does not claim to detect it.

### A Japanese locale breaks the firewall check

The wrapper forces `LC_ALL=C.UTF-8`, and `install.sh` gets the same value because it ends by running the wrapper. With the mise release that `min_version` names, a Japanese locale breaks the firewall check, because mise decides that ufw is active by matching the English line `Status: active`. Under a Japanese locale, `mise bootstrap` then reports firewall drift forever. The desktop session sets such a locale, and ssh forwards `LC_ALL`, which sudo keeps. On those machines, run raw `mise bootstrap` commands with `LC_ALL=C.UTF-8` until mise pins the locale itself.

### A project that selects its own mise environment hides the modules

The selection is mise's `MISE_ENV`. A project that selects its own environment (`MISE_ENV`, or `env` in a project `.miserc.toml`) replaces it there, and module tools such as node and pi fail with `No version is set for shim`. The base tools still work. To keep the module tools in such a project, list the machine's modules in its `.miserc.local.toml` as well, for example `env = ["agent", "dev"]`. A process started through a shim passes `MISE_ENV=<modules>` to its children, and that value outranks the `.miserc.toml` of the project they run in. Run `mise -E agent,dev ...` there. mise has no setting that stops it passing `MISE_ENV` on.

### sshd Match blocks are only partly covered

sshd keeps the first value it reads, but a `Match` block overrides a global value for the users it matches. When any `Match` line exists in `sshd_config` or `sshd_config.d`, the hook therefore always takes the slow path and runs `sudo sshd -T -C user=<current user>,host=localhost,addr=203.0.113.1`. That catches `Match all` and `Match User <current user>`. It does not see a `Match` for another user or for an address, and it does not see a `Match` in a file outside those two paths. The check covers the current user's effective settings, not every possible login.

### Secrets

- The task is `raw=true`. Without it, mise stops feeding stdin to a task once the selected `secrets` module has values to redact. Every `djd secret set` after the first then stored an empty value and exited 0, and `djd doctor` still said ok, because an empty value decrypts. The image test sets two values in a row with the module selected and reads both back.
- A decrypted value goes through the `$VAR` and `{{ }}` expansion of mise. A value stored as `pw$HOME-end` comes back with `$HOME` replaced, and an undefined `${USER}` prints a mise warning on every call. Do not store a secret that contains `$` or `{{`. The investigation found no mise setting that turns the expansion off.
- `age.strict = false` is deliberate. With strict on and the module selected, a machine without the key fails every mise command, including `djd secret keygen`, `djd doctor`, `djd module remove secrets`, and every shim, so the machine cannot recover itself. With strict off, a machine without the key keeps working with the values unset. That setting also hides a wrong or unreadable key, so `djd doctor` runs `mise env` with `MISE_AGE_STRICT=true`. It fails when the secrets module is selected and the key is missing, has a group or other permission bit (0600 and 0400 pass), or cannot decrypt a value.
- One key serves all your machines. Copy `age.txt` to each one and keep an offline backup, for example in a password manager. If you lose every copy, the values are unrecoverable. mise has no rekey command, so adding a recipient means entering each value again.

### Brave in a container runs without its sandbox

Brave aborts inside a container unless it runs with `--no-sandbox`, because Docker's default seccomp policy blocks namespace creation (tested on OrbStack in November 2026). The flag also switches off Brave's renderer seccomp-bpf sandbox. The Dockerfile adds it to a user-level copy of the menu entry, and the module does not, so a VM keeps Brave's sandbox. The image test starts Brave through that entry, and with the system entry instead Brave aborts with `Failed to move to new namespace`. A seccomp profile that allows user namespaces would keep Brave's sandbox on without `SYS_ADMIN`, but it applies only to containers started with it, so `docker run` of the published image would still abort. The repository ships none. One that added `clone`, `unshare` and `setns` to Docker's default made `unshare -Ur true` work, but it killed the XFCE session about 4 s after login (`xfce4-panel` aborted in libwnck with `default_icon_at_size: assertion failed`), and `test:desktop` failed on it twice out of two; Docker's own profile passes. The cause was not established (a guess: image loading falls back to a sandbox that needs more syscalls once user namespaces work). [SECURITY.md](../SECURITY.md#the-desktop) states the trade.

### The in-app updaters of Zed and Zen

Zed and Zen each carry an in-app updater that would replace files in the mise install directory without mise's digest check and without the release age. `ZED_UPDATE_EXPLANATION` in the base `[env]` makes Zed skip its update poll, and the Zen `postinstall` writes `distribution/policies.json` with `DisableAppUpdate` and `DisableTelemetry`. A headless screenshot of Zen's `about:policies` listed both as active (November 2026). Updates go through `mise upgrade`. Two other kinds of update are not switched off: Obsidian and Ferdium (Electron) update themselves after their first launch, so a pin holds only until then (see the comment in `config.toml`), and omp has `update.auto` and `marketplace.autoUpdate` on in its own `config.yml`, which is deliberate, because pi and omp are exempt from the release age. mise also puts a tool's own bin directories ahead of `PATH` while a `postinstall` runs, so both scripts reset `PATH` to `/usr/bin:/bin`, and `filter_bins` limits what each tool puts on `PATH`.

## Tooling quirks

- **multipass on macOS.** `multipass exec` spins at 100% CPU forever when its output goes to `/dev/null`, so `test:vm` reads the cloud-init wait through a pipe. `multipass exec` also arrives over ssh, and mise refuses to set the firewall to default deny for an ssh-derived process without `SSH_CONNECTION`, which `sudo -i` drops; `vm_sh` keeps it with `--preserve-env`.
- **act.** The Docker daemon may not be on the machine that runs the script, so a bind mount of a path made with `mktemp` shows the container nothing. `test:desktop` copies the secret in with `docker cp`. The `vm` job does not run under act, and `.actrc` maps the runners to a 24.04 image.
- **The GitHub API.** Anonymous callers get 60 requests an hour, which makes `ssh-import-id gh:` and mise's `github:` tools fail with 403; a token without scopes lifts it ([SECURITY.md](../SECURITY.md#github-tokens)).

## Costs accepted

### The desktop is part of every machine

What that costs, so it is a decision and not an accident: the image is about 2.6 times the size of the old sandbox (6.4 GB against 2.5 GB, measured on arm64), a headless server installs XFCE it never shows, and xrdp listens on 3389 on every machine. Only the `server` module adds the firewall rules that limit RDP to loopback and private networks, and `djd module add` warns when it is not selected. In a container the port is published by docker, and `compose.yaml` binds it to `127.0.0.1`.

## RDP security and known limits

xrdp 0.10.1 on Ubuntu 26.04, probed in November 2026 with FreeRDP 3.32.1 from a container against a server container on an arm64 host. The client image is amd64 and ran emulated. [SECURITY.md](../SECURITY.md#known-limits-of-the-rdp-service) summarizes the limits for reporters. This section keeps the evidence.

The repository sets three things, and `djd doctor` and `test:desktop` check the first two.

| Setting | File | Value | Set by |
| --- | --- | --- | --- |
| `security_layer` | `/etc/xrdp/xrdp.ini` | `tls` | `hooks/desktop-final` |
| `AllowRootLogin` | `/etc/xrdp/sesman.ini` | `false` | `hooks/desktop-final` |
| TLS key and certificate | `/etc/xrdp/key.pem`, `cert.pem` | new at every container start | `.devcontainer/desktop-entrypoint.sh`, with `make-ssl-cert generate-default-snakeoil --force-overwrite` |

Everything else is the xrdp package default.

### Protocol negotiation

Server with `security_layer=tls`. Each row is `xfreerdp3 /v:srv /u:dayjobdoor /p:... /cert:ignore <option>`, read against the `Security protocol` line of `/var/log/xrdp.log`.

| Client option | Result | `xrdp.log` |
| --- | --- | --- |
| none, like mstsc | connects | `configured [SSL], requested [SSL\|HYBRID\|HYBRID_EX\|RDP], selected [SSL]` |
| `/sec:tls` | connects | `requested [SSL\|RDP], selected [SSL]` |
| `/sec:nla` | refused, exit 133 | `requested [SSL\|HYBRID\|RDP], selected [SSL]`, then `SSL_accept ... unexpected eof` |
| `/sec:ext` | refused, exit 133 | `requested [SSL\|HYBRID\|HYBRID_EX\|RDP], selected [SSL]` |
| `/sec:rdp` | refused, exit 147 | `requested [RDP], selected []` |

- NLA does not exist in this xrdp. Nothing in `xrdp.ini` or the library offers CredSSP, and `sesman.ini` has no domain or authentication backend setting. A client that insists on CredSSP aborts, because the server picks TLS.
- `security_layer=hybrid` is not a valid value. The string `security_layer=%s is not recognized, will use security_layer=negotiate` is in `libxrdp.so`. A throwaway container with `hybrid` logged `configured [SSL|RDP]`, which equals `negotiate`. A typo or an upgrade to `hybrid` silently re-enables the legacy RDP layer.
- `negotiate` on this build selects `[SSL]` for a default client, but it still accepts a client that forces the legacy RDP layer. `test:desktop` uses a `negotiate` container as the control for that reason.
- Windows App and mstsc offer SSL and HYBRID like FreeRDP does and should take SSL. That is an inference and was not tested. A client forced to require CredSSP behaves like `/sec:nla` and fails.

### TLS versions and ciphers

A script sent an X.224 request for TLS, then pinned each version.

| Probe | Result |
| --- | --- |
| TLS 1.0 and 1.1 | refused |
| TLS 1.2 | `ECDHE-RSA-AES256-GCM-SHA384` |
| TLS 1.3 | `TLS_AES_256_GCM_SHA384` |
| TLS 1.2 `AES128-SHA` | accepted, CBC with SHA-1 |
| TLS 1.2 `AES256-GCM-SHA384` | accepted, static RSA key exchange, no forward secrecy |
| TLS 1.2 `ECDHE-RSA-AES256-SHA384` | accepted, CBC |
| TLS 1.2 `aNULL:eNULL` | refused |

`ssl_protocols=TLSv1.2, TLSv1.3` matches the results. `tls_ciphers` is commented out in `xrdp.ini` (`#tls_ciphers=HIGH`), and the default admits the three weak rows. RC4 and 3DES were not exercised, because the client fell back to `AES128-SHA`.

### Certificate

| Fact | Evidence |
| --- | --- |
| Subject | `CN=<container id>`, with the same `DNS` entry as SAN, RSA 2048, sha256WithRSA, ten years, self-signed |
| Different between containers | the fingerprints of two containers of the image differ |
| New at every start | `docker restart` changed the fingerprint |
| Key file | `/etc/xrdp/key.pem` links to `/etc/ssl/private/ssl-cert-snakeoil.key`, `root:ssl-cert`, mode 640 |
| Name never matches | `/cert:deny` by hostname and by IP is refused with `CERTIFICATE NAME MISMATCH` |
| Trust on first use | `/cert:tofu` passes the first time and still prints the mismatch banner. FreeRDP also prints "host key has changed" on the very first connect when the name mismatches. That is its own wording and not a real change. |
| Pinned fingerprint | `/cert:fingerprint:sha256:...` is accepted |
| A hostname | A container started with `--hostname` gets that name as CN and SAN, which removes the mismatch for that name. It still fails `/cert:deny`, because the certificate is self-signed, and a connection by IP still mismatches. |

- A client that trusts on first use sees a "changed" warning after every container start, including each restart by `restart: unless-stopped`. This is a known limit. Use TOFU or a pinned fingerprint, because `/cert:deny` always fails.
- The built image keeps the snakeoil pair that `ssl-cert` made at build time, and anyone who pulls the image holds that key. The entrypoint replaces it at every start, and `test:desktop` checks that the served certificate differs from the image's and between containers.

### Limits and exposure

| Fact | Value or result |
| --- | --- |
| `MaxLoginRetry` | 4. It cuts only one connection. A new connection resets the counter. |
| Lockout across connections | None. Six wrong passwords on six connections, then the right one, logged in. Each failed guess costs about 2 s in `pam_authenticate`. |
| `faillock`, fail2ban | Neither is configured. |
| `TerminalServerUsers` | `tsusers`, a group that does not exist, with `AlwaysGroupCheck=false`, so everyone may log in. |
| `MaxSessions`, `KillDisconnected` | 50, and `false`: disconnected sessions live on, so agent work survives. |
| Sudo | `dayjobdoor` has passwordless sudo, so one guessed password is root in the container. |
| Password in argv | Only when it is passed as an argument, `djd-desktop-entrypoint dayjobdoor <password>`, which shows in `/proc/1/cmdline` of the container and in `docker inspect`. `compose.yaml` passes it as a secret instead ([SECURITY.md](../SECURITY.md#docker)). Inside the container, a process that runs as root can still read the file. |
| Listener | Only `xrdp`, on `[::]:3389` inside the container. `compose.yaml` publishes it on IPv4 loopback only. |
| `AUTHFAIL` log lines | They go to `/var/log/xrdp-sesman.log`, where a log watcher could read them. |

Parallel connections multiply the guess rate. That is an inference and was not run. Password strength and the loopback binding are the only real defences.

### Channels

| Channel | State | Finding | Switch, not applied |
| --- | --- | --- | --- |
| clipboard (`cliprdr`) | on, both directions | A process in the session reads what you copy locally, such as a password manager entry. A process in the session can also overwrite your local clipboard, for example to plant a command. xrdp logs nothing for it. | `RestrictInboundClipboard=all` and `RestrictOutboundClipboard=all` in `sesman.ini`, or `cliprdr=false` in `xrdp.ini`. The keys take a comma list of `text`, `file`, and `image`. |
| drives (`rdpdr`) | on | `xrdp-chansrv` logs `Detected remote drive`, but nothing mounts. `fuse3` and `libfuse3-4` are installed, but `xrdp-chansrv` links no libfuse and has no fuse code, so no drive mounts even with `/dev/fuse` granted. `sesman.ini` sets `FuseMountName=thinclient_drives` and `FileUmask=077` for mapped drives, which would give every process of the user access to them. | `rdpdr=false` also closes printer and serial redirection. |
| playback (`rdpsnd`) | on | `xrdp-sink` and `xrdp-source` exist and are the defaults. | `rdpsnd=false` |
| microphone | `xrdp-source` always exists | It carries audio only if the client opts in. A process of the same user can record from it then. Only silence was seen, and real microphone data was not tested. | The microphone path needs `drdynvc` too. |
| `rail`, `xrdpvr` | on | Not tested. | `rail=false`, `xrdpvr=false`, untested |

A tested remedy for the ciphers is `tls_ciphers=ECDHE+AESGCM:ECDHE+CHACHA20` in a throwaway container. It refused the three weak suites, and a full FreeRDP connect negotiated TLS 1.3. The repository does not apply it, and old clients without ECDHE-GCM would not connect.

## Not verified

These statements are open ends, not known failures.

- Windows App and mstsc were not tried against the TLS-only xrdp; FreeRDP was.
- The README recipes were not run as written: the multipass launch with its `chpasswd` block, and the incus `passwd` and RDP steps. `test:vm` runs the part above the `# djd-install-below` line of `cloud-init/vm.yaml` and the install.
- The startup time of the sheldon plugin set was not measured. The old set measured 102.5 ms.
- `full-weekly.yaml` has not run since the desktop moved into the base, so its time and its disk use are unknown.
- A rebuilt image replaces a compose container, and the new one has none of the old container's files; this is compose's behavior and was not tested here.
- The repository settings in [guidance.md](guidance.md#harden-the-repository-settings) are not applied.
