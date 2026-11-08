# CI and release reference

Facts about the GitHub Actions workflows, the tests they run, and the release chain. [architecture.md](architecture.md#ci-mirrors-local-tasks-and-releases-are-safe-to-repeat) explains the decisions behind them, and [how-to.md](how-to.md) has the procedures.

## Workflows

| File | Runs on | Permissions | Does |
| --- | --- | --- | --- |
| `ci.yaml` | Pushes to `main`, pull requests, a weekly schedule, and `workflow_dispatch` | `contents: read` | Runs the jobs below. |
| `docs.yaml` | Pushes to `main` and pull requests that touch `docs/**`, `**/*.md`, or `llms.txt`, except `agent/**` | `contents: read` | Runs two jobs. `lint-docs` runs `mise run lint:docs`, and `secrets` runs `mise run lint:secrets` (gitleaks over the whole history). Both check out with `fetch-depth: 0`, and `mise-action` installs only mise (`install: false`). `secrets` sets `MISE_LOCKED` and receives no token. It never releases. |
| `tag.yaml` | A completed `ci.yaml` run on `main` | none at the top. The job has `contents: write`, `actions: write`, and `checks: read`. | Tags and releases a commit that passed, dispatches `push.yaml`, and waits for it. |
| `push.yaml` | A semver tag push, or a dispatch by `tag.yaml` | none at the top. `build-images` has `contents: read` and `packages: write`, and `merge` has `packages: write`. | Publishes the images to GHCR. |
| `full-weekly.yaml` | A weekly schedule and `workflow_dispatch` | `contents: read` | Builds the `full` image, runs `djd doctor` in it, then runs `djd update` and `djd doctor` in it. It sits outside the release chain, so a red run never blocks a release. |

`ci.yaml` skips a push or pull request that touches only `docs/**`, Markdown files, or `llms.txt`, except `DESIGN.md` and `agent/**`. The two `agent/**/AGENTS.md` files ship in the images and the sandbox test compares them, so a change there runs CI, tags, and releases. `lint` checks `DESIGN.md`, so a change to it runs both `ci.yaml` and `docs.yaml`. `docs.yaml` takes the other side of the filter for everything else, so a docs-only change still gets `lint:docs`, which checks links, anchors, repo paths, commands, `DJD_` variables, and the test list, and a gitleaks scan, because a Markdown file can hold a key as well as any other.

The weekly schedule catches upstream breakage, because tools track `latest`. Scheduled runs never release, because `tag.yaml` accepts push runs only. Each event has its own concurrency group, so a scheduled run never cancels the push run that a release waits for.

GitHub disables scheduled workflows in a public repository after 60 days without repository activity. That stops the weekly `ci.yaml` run and `full-weekly.yaml` without a message. Enable them again in the Actions tab.

## CI and release chain

```mermaid
flowchart LR
    push[push to main] --> ci
    pr[pull request] --> ci
    cron[weekly schedule] --> ci
    ci["ci.yaml<br>lint, sandbox, desktop, vm"] -->|push run passed| tag["tag.yaml<br>X.Y.Z tag and release"]
    tag -->|dispatch, then wait| pub["push.yaml<br>build, smoke test, merge tags"]
    manual[manual X.Y.0 tag] --> pub
    pub --> ghcr[(GHCR sandbox and desktop)]
    docsonly[docs-only push or pull request] --> docs["docs.yaml<br>lint:docs, lint:secrets"]
    cron2[weekly schedule] --> full["full-weekly.yaml<br>outside the release chain"]
```

## Timeouts

| Job | Timeout | Measured |
| --- | --- | --- |
| `ci.yaml` `lint` | 15 min | 22 s |
| `ci.yaml` `sandbox` | 25 min | 158 s on amd64, 129 s on arm64 |
| `ci.yaml` `desktop` | 25 min | 353 s on amd64, 294 s on arm64 |
| `ci.yaml` `vm` | 25 min | 200 s on amd64, 166 s on arm64 |
| `docs.yaml` `lint-docs` and `secrets` | 10 min each | not measured |
| `push.yaml` `build-images` | 45 min | 2 to 5 min |
| `push.yaml` `merge` | 10 min | not measured |
| `tag.yaml` release job | 60 min | 8 min 9 s for release 0.0.6 (5 November) and 7 min 10 s for release 0.0.7 (6 November), the two runs that waited for `push.yaml` |
| `full-weekly.yaml` | 60 min | about 21 min |

The measured values are medians of recent runs, read from the run history up to 1 November 2026, except the `tag.yaml` row, which gives the two runs that waited. A timeout covers the slowest expected case with room, and it also limits how long a hung job holds its token. `full-weekly.yaml` prints `df -h /` first, because its one red run died with `No space left on device` and left no log.

The `ci.yaml` run of 6 November 2026 (commit f111319) took 29 s for `lint`, 230 s on amd64 and 180 s on arm64 for `sandbox`, 449 s and 385 s for `desktop`, and 199 s and 159 s for `vm`. `sandbox` and `desktop` were slower than the medians. The timeouts leave room for that.

## Jobs in ci.yaml

Every job runs a mise task that you can run locally. `make <task>` runs `mise run <task>`.

### lint

`mise run lint` runs six checks in parallel. Each check installs only its own tools. `lint` has no body of its own. It depends on the six `lint:*` tasks.

- `lint:shell` runs shellcheck and `shfmt -i 4` over every file whose first line is a `sh` or `bash` shebang, plus `home/.profile`, `.bash_profile`, and `.bashrc`, and `zsh -n` on each zsh startup file separately. It does not lint the inline `postinstall` scripts in the TOML files. When `shfmt` finds a difference, it prints `lint: shell is not formatted; run mise run lint:fix`.
- `lint:config` runs `mise fmt` and `mise tasks validate`. It skips the gitignored `*.local.toml` files. It also requires that the `min_version` line of `mise.toml`, the `min_version` line of `mise-config/config.toml`, and every `jdx/mise-action` step (an unquoted `version:` line) name the same mise release, because no bot bumps them. `install.sh` is not a pin, because it reads `min_version`. The check fails and names the source when a pin is missing or reformatted.
- `lint:workflows` runs jactionlint over the workflows and `dependabot.yml`, compares the runner labels with `.actrc`, and runs hadolint. It fails on a workflow named `*.yml`, because the other checks read `*.yaml` only.
- `lint:design` lints `DESIGN.md`.
- `lint:docs` runs the checks in the next list, and also runs alone in the `lint-docs` job of `docs.yaml`.
- `lint:secrets` runs gitleaks over the whole git history. When there is no git directory, it runs over the files, so the secret scan never skips.

`lint:fix` rewrites shell and mise TOML formatting.

`lint:docs` needs only bash, takes 10 to 20 s, and checks that:

- Relative Markdown links and anchors resolve, `llms.txt` included. It ignores headings inside code fences.
- Every repo path in an inline code span exists. A leading `./` is allowed, and a path under a top-level name that existed in the git history but not now is reported. Without a git history, as in the docker lint run, only today's names count.
- Every `mise run` and `djd` command in a span names a real task or command, and every word after `make` does.
- Every `DJD_` variable in the docs appears in the code.
- Every `DJD_` variable in the code appears in some doc. `DJD_BAD`, `DJD_CHECK` and `DJD_CHECK2` (secret names that `test` makes up) and `DJD_COMMANDS` (a Makefile variable) are exempt.
- Every `tests/*.sh` is named in `docs/reference.md` and is run by a task under `mise-tasks/`. A bare name inside a quoted or space-delimited list counts as a reference, so a test with a common word for a name could pass trivially.

### sandbox, on amd64 and arm64

The `test` task builds the sandbox image and then runs these steps in order. Each step uses a throwaway container of the image, and the test checks exit statuses, not only output.

| # | Step | Must hold |
| --- | --- | --- |
| 1 | Offline tests | `mise run test:offline` passes (see the test map below). |
| 2 | Doctor | `djd doctor` passes and prints an `ok` line for each of `ubuntu`, `mise-config`, `login-shell`, `bootstrap`, and `dotfiles`, because a doctor that skipped a check would still exit 0. |
| 3 | Tools on `PATH` | A plain `docker run` finds `rg` without a login shell. |
| 4 | `.profile` | `~/.profile` alone puts the shims on `PATH`, tested with `env -i`. |
| 5 | Agent module | A shimmed `node` sees `PI_TELEMETRY=0` and `DO_NOT_TRACK=1` without a login shell. `~/.pi/agent/AGENTS.md` and `~/.omp/agent/AGENTS.md` are non-empty links into the checkout's `agent/` directory, and their content is the same. |
| 6 | Silent shells | Interactive zsh and bash start silently on a tty. The first zsh start fills the init cache, so the test drops its output. The second zsh start and a bash start must print nothing. |
| 7 | Login banner | `zsh -lc` and `zsh -lic` output contain no `.zlogin` banner. With the banner tools stubbed to print distinct text, an interactive login shell that reads its commands from stdin prints exactly the two banners and the `.zlogout` farewell. |
| 8 | Doctor, release and shell | `djd doctor` fails for an `os-release` that is not Ubuntu 26.04 and for a login shell that is not zsh, and passes again after each repair. |
| 9 | Doctor, sshd | The scenarios in the stub table below. |
| 10 | Doctor, xrdp | The xrdp scenarios in the stub table below. |
| 11 | Backup and relink | One container backs up a conflicting file, relinks a moved checkout through `install.sh`, and converges (next list). |
| 12 | Directory link | A directory link into the checkout (`~/.config/lsd`) is not moved aside by `hooks/dotfile-conflicts`, and no tracked file is renamed. |
| 13 | Status | `djd status` exits 0 and prints the revision, which the image carries because it has no `.git`. |
| 14 | `install.sh` | It replaces a mise older than `min_version` and leaves the image's own mise alone, and its own apply succeeds on the image. A stub `curl` (which honors `-o`, as `install.sh` saves the script to a file) records `MISE_VERSION`, and a stub mise reports 2000.1.1. The run must end at the version check, with the message `installing mise failed`. It records `v<min_version>` by default and `v2099.1.1` for `MISE_VERSION` with or without the `v`. |
| 15 | Secrets | A secrets round trip works (the list after the stub table). |

Step 11 in detail:

- `djd apply --dry-run` leaves a conflicting file in place and creates no backup.
- A real apply moves the file aside.
- `~/.dotfiles` is a link to the checkout, and the checkout moves, so the link dangles. `install.sh` removes it and links the new location.
- A successful apply clears the zsh and bash init caches.
- Converging means that `djd doctor` and `mise bootstrap plan --detailed-exitcode` both pass.

`djd doctor` must print the line named in the table for each of these stubs, in a throwaway container, and exit non-zero whenever that line is a `FAIL`:

| Stub | Doctor must report |
| --- | --- |
| `os-release` with another `VERSION_ID`, or with `ID=debian` | `FAIL ubuntu` |
| the login shell set to bash | `FAIL login-shell` |
| the stock sshd layout with `10-djd.conf` | `ok sshd` |
| the stock layout, with a stub that reports passwords on | `ok sshd`, because the stock layout needs no `sshd -T` |
| `Match all` with `PasswordAuthentication yes`, where the sshd stub honors `-C` and the hook has to pass it | `FAIL sshd` |
| `Match User nobody` with `X11Forwarding no` | `ok sshd` |
| an earlier drop-in that turns passwords on | `FAIL sshd` |
| an earlier drop-in that changes nothing | `ok sshd` |
| an `sshd_config` that does not start with the `Include`, with a stub that reports passwords on | `FAIL sshd` |
| the same file, with a stub that reports passwords off | `ok sshd` |
| a drop-in with an `Include`, or one this user cannot read (mode 0600), with a stub that reports passwords on | `FAIL sshd`; with the stub reporting off, `ok sshd` |
| the server module selected but never applied | `FAIL bootstrap` |
| `XDG_CONFIG_HOME` elsewhere, with the doctor script run directly | `FAIL mise-config` |
| `security_layer=negotiate` in `xrdp.ini` | `FAIL xrdp-tls`, and `ok xrdp-root-login` |
| `security_layer=tls` only as a comment | `FAIL xrdp-tls` |
| `AllowRootLogin=true` in `sesman.ini` | `FAIL xrdp-root-login`, and `ok xrdp-tls` |
| a real file in place of a dotfile | `FAIL dotfiles`, and the output lists the file |

Every `FAIL sshd` line must also say `not keys-only`. The hook cannot see a `Match` for another user or for an address ([scope](architecture.md#a-module-is-a-mise-config-environment)), so the test stops at `Match all` and a harmless `Match`. A real sshd evaluates `Match` blocks only with `-C`, which is why the stub does the same.

The secrets round trip, step 15:

- The key has mode 600 and its directory mode 700, and `djd secret keygen` refuses to overwrite it and leaves it unchanged.
- The first `djd secret set` runs with the module unselected, the usual case, and the module is selected before the second. Both values decrypt through `mise exec`. This is the test of the `raw=true` task ([architecture.md](architecture.md#secrets-use-the-age-support-of-mise)).
- The ciphertext lands in `config.secrets.toml` without the plaintext.
- `djd secret set NAME=value` exits 2 and writes nothing.
- `djd doctor` reports the secrets module as ok, then as failed for a missing key, for a different key, and for a key with any group or other bit (0400 and 0600 pass), and each failure names its own cause.

### desktop, on amd64 and arm64

The `test:desktop` task builds the desktop image and starts a server container, plus a control container of the same image with `security_layer=negotiate` and `AllowRootLogin=true`. The client is an `ubuntu:26.04` container with `freerdp3-x11`, `xvfb`, and `procps`, installed before the clock starts. The first login gets 120 s. The test runs these stages in order.

| # | Stage | Must hold | Why |
| --- | --- | --- | --- |
| 1 | RDP login | An xfreerdp client logs in and XFCE starts through `~/.xsession`. The environment of `xfce4-session`, read as its owner, has `GTK_IM_MODULE=fcitx`, `QT_IM_MODULE=fcitx`, `XMODIFIERS=@im=fcitx`, and `LANG=ja_JP.UTF-8`. | `.xsession` exports the fcitx variables. The system locale comes from PAM and `/etc/default/locale`, and it has to win over the `LANG=C.UTF-8` of the container. Root cannot read another user's `/proc/PID/environ` in a container, so the owner does. The `desktop` job of the CI run of 6 November 2026 (commit f111319) passed this assertion on a built image, so PAM's value wins over the container's `LANG`. |
| 2 | TLS key | The fingerprints of the server, the control, and the certificate that the image was built with all differ. | Every container would otherwise share one key, and anyone who pulls the image holds it. |
| 3 | Legacy layer | `xfreerdp3 /sec:rdp`, logged in as a throwaway account `probe`, is refused by the server. Its `xrdp.log` says `requested [RDP], selected []`, no `probe` session starts, and the first session stays up. The control accepts the same client (`selected [RDP]`, and the client stays connected). | Without the control, a client that cannot speak the legacy layer would pass the refusal on any server. The second account shows that a wrongly accepted client would start a session of its own. |
| 4 | Root login | Root gets a password in both containers. The control starts a root `xfce4-session`. The sesman log of the server says `ROOT login attempted, but root login is disabled`, and no root session starts. | The refused client stays at the login screen, so its exit code cannot show a refused root login. |
| 5 | Password secret | The entrypoint sets the password of `ubuntu` from `/run/secrets/djd_rdp_password` when no argument gives one, and refuses to start with neither. | `compose.yaml` passes the password as a secret, because an argument shows in `docker inspect` and `/proc/1/cmdline`. The image itself has no password for `ubuntu`, which is the control. |
| 6 | Audio defaults | `pactl get-default-sink` prints `xrdp-sink` and `pactl get-default-source` prints `xrdp-source`. Then the test kills wireplumber, and a new wireplumber process must appear within 30 s with the same two defaults. | This shows that `~/.xsession` started PipeWire and that the autostart entry of `pipewire-module-xrdp` loaded both devices and made them the defaults through `pactl`. The source check matters, because the container has only one sink and wireplumber would pick it without the script. The defaults live in the metadata of wireplumber. The client has no audio device and plays nothing, so the test proves the setup and not the sound. |
| 7 | Apps | `tests/desktop-apps.sh` runs as the desktop user with `DJD_APPS_LAUNCH=1`. For each of brave-browser, ghostty, zen, and zed, the command resolves and prints its version, and the menu entry exists with an `Exec` that resolves. Brave runs that `Exec` line, which carries `--no-sandbox` in the image, plus `--headless=new --dump-dom about:blank`, and the output contains `<html`. Zen runs `--headless --screenshot` and writes a PNG. Ghostty and Zed start inside the RDP session, and each shows a new visible window of its own `WM_CLASS` within 30 s. A window that an earlier launch left does not count. The test logs how long each took. | The VM test runs the same script without the variable. |
| 8 | Supervisor | `tests/xsession-audio.sh` runs as the desktop user. | See the list below the table. |
| 9 | Logout | The test ends `xfce4-session`, which also ends the session bus. No `pipewire`, `pipewire-pulse`, or `wireplumber` of the user remains after 30 s. A second login gets the same two audio defaults from daemons with new PIDs. | Before `~/.xsession` ended what it started, the daemons outlived the logout, and the supervisor started a `wireplumber` against the dead bus. |
| 10 | Container restart | The test restarts the server container, logs in again, and repeats the sink and source checks. | A restart leaves the stale PipeWire socket of the first session in `/run`, and `~/.xsession` must not take it for a live server. The client disconnects first, because it could otherwise reconnect and make the wait pass on its session. |

`tests/xsession-audio.sh` runs the real `~/.xsession` against stub daemons, and the sandbox test runs it too. It took 31 s in an `ubuntu:26.04` container on a Mac (measured once). It checks that:

- The desktop starts without waiting for a server that is still starting.
- wireplumber starts after the server answers and again after it dies.
- A wireplumber that keeps dying is given up on after five quick runs, while a 30 s run resets the count.
- The session bus is made with `--exit-with-session`, so it ends with the session.
- A server that never answers prints one line to stderr and nothing to stdout, and starts nothing.
- A server that stops answering gets no new wireplumber, and the supervisor itself ends.
- A server that already answers is left alone.
- Nothing the script started outlives the desktop.

It needs Linux, because it finds leftovers through `/proc`.

### vm, on amd64 and arm64

The `test:vm` task starts a fresh Ubuntu 26.04 machine from `cloud-init/vm.yaml`. In CI that is an incus system container (`images:ubuntu/26.04/cloud`). It pipes `install.sh` into `sh -s -- server desktop`, as the README does, with the tree under test as the clone source. Both the install and `tests/vm-checks.sh` run with `DJD_SKIP_SSH_CHECKS=1`, because the VM has no authorized key, which the server module's `post-packages` hook would otherwise refuse. Then `tests/vm-checks.sh` runs inside it. The script refuses to run unless `DJD_TEST_VM=1`, and exits 2 with a message that names `mise run test:vm`, because it changes the machine: ufw rules, an sshd drop-in, and module removals. Only `test:vm` sets the variable. `test:vm` names the VM `djd-test-<pid>-<random>`, and it waits for cloud-init for at most 900 s (`timeout 900` runs inside the VM). A timeout prints `vm: cloud-init did not finish within 900 s`, and a cloud-init failure prints `vm: cloud-init failed (exit N)` followed by `cloud-init status --long`. The EXIT trap of `tests/vm-checks.sh` removes the test container, its network, and the sshd guard drop-in, so a failed or interrupted run leaves none of them. The checks are:

- Both cloud-init files pass the cloud-init schema check.
- `djd doctor` passes, also under a Japanese locale, where a control shows that `ufw` would print its status in Japanese. It reports ok for the sshd and xrdp checks.
- ufw has the expected default policy and rules, with RDP open to private networks only.
- sshd accepts keys only. A drop-in that sorts first with `PasswordAuthentication yes` makes `djd apply` fail and `djd doctor` report `FAIL sshd`. Both succeed again after the file is removed.
- A container published with `-p 80` listens on `127.0.0.1` only, on the default bridge and on a new network.
- `ssh.socket`, avahi-daemon, xrdp, and docker are active.
- The running xrdp started after the last change to `xrdp.ini` and `sesman.ini`, so the hardened settings are in the daemon and not only in the files.
- The user is in the docker group.
- `/etc/default/locale` and the generated `ja_JP` locale exist.
- The HackGen font is installed, which `fc-list` shows as `HackGen35 Console NF`.
- `mise bootstrap plan --detailed-exitcode` reports no changes.
- `djd module remove desktop` and `djd module remove server` succeed. The sshd drop-in and `daemon.json` disappear, Brave's apt source goes with `desktop`, and the ufw SSH rule stays.
- Brave's menu entry carries no `--no-sandbox`. Only the Docker image adds it.

The task uses the first of incus, multipass, and OrbStack (`orb`) that it finds. CI installs incus from the Ubuntu archive, initializes it with `incus admin init --minimal`, and opens the daemon socket to every user on the runner (`chmod 666`). It also accepts the `incusbr0` bridge in Docker's `DOCKER-USER` chain, because Docker sets the `FORWARD` policy to `DROP` and would cut the containers off. On a Mac, `make test:vm` runs the same checks with multipass or OrbStack. All three get the checkout through `tests/tree.sh`. The VM is deleted at the end of a run. `DJD_KEEP_VM=1` (exactly `1`) keeps it, to inspect a failure.

[how-to.md](how-to.md#try-it-in-an-orbstack-machine) records the one run of `test:vm` on OrbStack.

## Test map

| Script | Proves | Run by | Where |
| --- | --- | --- | --- |
| `tests/xsession-audio.sh` | The `~/.xsession` supervisor | `test:offline`, `test:desktop` | Sandbox image, desktop container |
| `tests/djd-module.sh` | `djd module` with a stub `mise`: selection order, the secrets-with-agent warning, empty `MISE_ENV` items, the server-removal warning, the exit 2 and message for a missing or unknown module name, and the removal of Brave's apt source | `test:offline` | Sandbox image |
| `tests/server-hooks.sh` | The server `post-packages` hook refuses an apply that would lock the user out of ssh, says why, and leaves the user out of the docker group when it refuses | `test:offline` | Sandbox image |
| `tests/tree-check.sh` | What `tests/tree.sh` leaves out of the archive, judged by the repository's own `.gitignore`: it runs in an empty `HOME`, has one canary file for each kind of secret the `.gitignore` covers, and plants a hostile global ignore file and `core.excludesFile` that the archive must not reflect | `test:offline` | Sandbox image |
| `tests/desktop-apps.sh` | The four desktop apps | `test:desktop`, `tests/vm-checks.sh` | Desktop container, VM |
| `tests/vm-checks.sh` | The server and desktop install, including that xrdp runs with the hardened settings | `test:vm` | incus, multipass, or OrbStack |
| `tests/tree.sh` | Helper, not a test | `ci`, `test:vm`, `test:offline`, the no-trust flow in AGENTS.md | Host |

The tasks:

| Task | Runs |
| --- | --- |
| `mise run test:offline [test]...` | The offline tests, with no network and no token, on the current tree inside an existing `djd:sandbox`, with no build. `--image` names another image. |
| `mise run test` | `build sandbox`, then `test:offline`, then the steps of the sandbox table above. |
| `mise run test:desktop` | `build desktop`, then the stages of the desktop table above. |
| `mise run test:vm` | The VM test. |
| `mise run lint:docs` | The doc checks, with bash alone. |

`test:offline` streams `tests/tree.sh` into one container per test, creates the Brave apt source first (`tests/djd-module.sh` fails when that file is missing, unless `DJD_MODULE_NO_BRAVE=1` skips that part), and prints `== <test>` before each. The containers have no network (`--network none`), so "offline" is enforced, and the tests run on the current tree and not on the copy that the image holds. The run took about 40 s on an existing image in November 2026, with one more test than today, and has not been timed since. `tests/xsession-audio.sh` is the slow test. The names are listed in `mise-tasks/test/offline`, twice. They are the choices of the `[test]...` argument and the default list in the `read` line. A new offline test needs its name in both places.

Where a new test goes:

| What it checks | Where |
| --- | --- |
| Logic of a djd task or hook, with stubs | `tests/<name>.sh` with a `# Contract` header, listed in `mise-tasks/test/offline` and named in [reference.md](reference.md#layout) |
| A `djd doctor` check | A `doctor_says` step in `mise-tasks/test/_default` |
| Something that needs systemd, ufw, sshd, or docker | `tests/vm-checks.sh` |
| Something that needs RDP or X | `mise-tasks/test/desktop` |

`lint:docs` fails when a `tests/*.sh` is in no task or is not named in `docs/reference.md`.

## Failure output

The test tasks print `FAIL line N: <command>` to stderr when a command fails. With `GITHUB_ACTIONS` set, the ERR traps of `test`, `test:desktop`, `test:vm`, and `tests/vm-checks.sh`, and the `fail()` helper of `test:desktop`, also print `::error::<cause>`. The cause is the line number and the command, with newlines flattened and cut to 300 characters. `gh run view <id>` lists these annotations without the log. `test:vm` passes `GITHUB_ACTIONS` into the VM, so `tests/vm-checks.sh` annotates too.

Two failures do not annotate their cause. A failure inside a container script of `test` annotates the outer `docker run` line, and the inner message stays in the log. The explicit `echo ...; exit 1` failures of `tests/vm-checks.sh` do not trigger the ERR trap, so only their log lines show them.

## Repo tasks

Repo tasks are mise file tasks in `mise-tasks/`, plus a few in `mise.toml`. Each task declares its description, its arguments with `#USAGE` and `choices`, its dependencies, and the tools it needs with `tools` or a `#MISE tools=` header. `test` depends on `build sandbox`, so `mise run test` builds what it tests. `mise tasks validate` checks the definitions, and the file tasks are plain bash that lint checks like every other script.

`mise.lock` pins tool versions with checksums for the platforms in `lockfile_platforms` in `mise.toml`: `linux-x64`, `linux-arm64`, and `macos-arm64`. `mise lock --bump` moves the pins without installing anything. The npm graph that sits beside the lock is in `.mise/locks/`. `npm.package_manager = "aube"` in `mise.toml` selects it, because the bun of the agent module cannot install a locked aube graph.

The `lint` job sets `MISE_LOCKED=true`. Its install uses only the URLs and checksums in `mise.lock`, so its install steps call no GitHub API and need no token, and it fails when the lock lacks a tool. [SECURITY.md](../SECURITY.md#github-tokens) says which token each workflow step receives. `min_version` in `mise.toml` and in `mise-config/config.toml` makes an older mise stop with an error.

In the sandbox image, `mise run lint:shell` from an empty mise data directory installed two tools in 7 s. The whole parallel `lint` took 42 s, including seven tool installs. Both numbers were measured once, in October 2026, on an arm64 Mac running OrbStack, and cannot be reproduced from this repository.

## Running CI with act

`mise run ci [job...]` runs the jobs `lint`, `sandbox`, and `desktop` with [act](https://github.com/nektos/act). All three run by default. The task stops unless `GITHUB_TOKEN` is set, and it checks that before it builds the scratch repository that act runs on. The `vm` job is not offered. [How to run CI locally](how-to.md#run-ci-locally) shows the commands.

- `.actrc` maps the `ubuntu-26.04` runners to `ghcr.io/catthehacker/ubuntu:act-24.04`, because catthehacker publishes no 26.04 image.
- `mise run ci --dry-run` plans every job of `ci.yaml`, `docs.yaml`, `full-weekly.yaml`, `tag.yaml`, and `push.yaml` without running steps, and it rejects job names. It feeds the release workflows a sample tag push and a sample CI `workflow_run` event.
- act receives a copy of the tracked and unignored files from `tests/tree.sh`, which skips files that are deleted but not yet staged and ignores the git configuration and global ignore file of the host. `age.txt`, `miserc.local.toml`, and the `.secrets` file of act never enter its containers.
- Lint fails on any `ubuntu-*` runner label that `.actrc` does not map, because act stops at an interactive image prompt for an unmapped label.
- The `vm` job needs incus. It runs only on GitHub or through `make test:vm`.

## Release chain

`tag.yaml` runs after a CI run from a push to the `main` branch of this repository passes.

- It releases a commit only when the commit contains the newest `X.Y.Z` tag. For any other commit it prints a `::warning::` and ends green, so a release that was held back shows in the run summary.
- It bumps the patch number only. A minor or major bump is a manually pushed `X.Y.0` tag, and `push.yaml` builds images for it. If that tag already points at the commit that CI on `main` just finished, `tag.yaml` reuses it. It creates the release if none exists, and it dispatches `push.yaml` again. The dispatch is in the concurrency group of `push.yaml`. If the run that the tag push started is still going, the dispatch cancels it. If that run has finished, the dispatch rebuilds the images and overwrites them.
- It stops with an error that says to run it again when the patch tag it computed appears on the remote between its fetch and its check. A minor or major tag pushed in that window is not detected. It never cancels a release that is running. The concurrency group sits on the release job, so only runs that pass the job's `if` (a green push run of this repository) queue. One run waits per group, and a newer waiting run replaces an older one. The commits of the replaced run are inside the tag of the newer run.
- Tags are strict SemVer without leading zeros (`1.2.08` is not a release tag), because a leading zero breaks the patch arithmetic.
- It marks a GitHub release `latest` only when its tag is the newest.
- It writes the release notes itself. They list the commits since the previous `X.Y.Z` tag and the `docker pull` commands for both images, because `--generate-notes` lists only pull requests and the pushes to `main` have none.
- It creates the release first. Only a new release goes on to publish. A re-run of CI for a commit that already has a release finds it, prints the retry command, and dispatches nothing.
- It dispatches `push.yaml`, because tags that `GITHUB_TOKEN` pushes start no workflow, and records a UTC timestamp first.
- It finds the dispatched run by polling `gh run list` up to 12 times, 5 s apart, for a `workflow_dispatch` run of this tag that is not older than the timestamp. It takes the newest. When none appears within a minute, the step fails.
- It then runs `gh run watch --exit-status --compact --interval 30` on that run, so a failed publish fails `tag.yaml`. The person whose push produced the release gets the notification, because `push.yaml` itself runs as the bot. The job needs `checks: read` for this, because `gh run watch` reads check-run annotations and `GITHUB_TOKEN` lacks that once any permission is set. A newer `gh` may skip a failed annotation fetch, which was not confirmed.
- It holds its concurrency group while it waits, which took 8 min 9 s and 7 min 10 s in the two measured runs (see Timeouts). A later release queues behind it, and GitHub keeps only the newest pending run.
- A failed publish leaves the `tag.yaml` run red. Re-running it does not retry the publish, because the release exists. [Retry a failed publish](how-to.md#retry-a-failed-publish) has the steps.

The wait and the smoke test have run on GitHub: releases 0.0.6 (5 November 2026) and 0.0.7 (6 November 2026) passed the `tag.yaml` step "Trigger GHCR build and wait for it" and the smoke step of all four builds. No failed publish has turned the job red yet.

`push.yaml` builds each flavor for each platform with no build cache and pushes by digest. A smoke step then pulls the pushed image by digest and runs `docker run --rm "$REGISTRY_IMAGE@$DIGEST" sh -c "$SMOKE"`. `SMOKE` is `djd doctor` for both flavors, so each flavor and each architecture runs it on its own runner. The merge job creates the multi-arch tags only when every leg passed, so a red smoke test moves no tag. For the desktop flavor, doctor with `desktop` selected greps `xrdp.ini` for `security_layer=tls` and `sesman.ini` for `AllowRootLogin=false`. The desktop leg is the one most likely to fail first.

| Image | Tags that move with the newest release | Fixed tag |
| --- | --- | --- |
| sandbox | `sandbox`, `latest`, and `X.Y` | `X.Y.Z` |
| desktop | `desktop` and `X.Y-desktop` | `X.Y.Z-desktop` |

A tag push publishes only a commit that is on `main`: the first job of `push.yaml` asks the GitHub compare API and fails for any other commit, because anyone who can push a tag would otherwise publish an unreviewed commit with a `packages: write` token. A floating tag moves only when the release is the newest `X.Y.Z` tag. A fixed tag is written once per release, because a re-run of CI does not dispatch `push.yaml`. A retry rebuilds and overwrites it on purpose.

- The merge job writes `description`, `source`, `licenses`, and `version` as index annotations, because GHCR reads the description of a multi-arch package from the index. `docker buildx imagetools create` writes no index annotations unless you pass `--annotation`. A test against a local registry with a docker-container builder confirmed both facts, and the first release confirmed them on GHCR for `sandbox` and `desktop`.
- The images that `push.yaml` builds carry the commit in `DJD_REVISION`, because `.git` is not copied into them.
- GitHub documents private as the default visibility of a new package. The first release of this repository published it as public.

## Workflow audit

jactionlint audits the workflows, and lint runs it.

- Checkouts drop the token with `persist-credentials: false`, except in `tag.yaml`, which pushes the tag.
- Every `uses:` is pinned to a commit.
- `push.yaml` and `tag.yaml` set `permissions: {}` at the top, and every job sets its own. Values such as `matrix.platform` and the build digest reach scripts through `env:`, not through `${{ }}` in the script.
- Both `setup-buildx` steps in `push.yaml` set `cache-binary: false`. The input has no effect while no buildx version is pinned; it keeps a pinned binary out of the Actions cache if one is added. The release builds use no layer cache because they set no `cache-from` or `cache-to`.
- Three findings are ignored inline, each with its reason beside it. One is the guarded `workflow_run` trigger in `tag.yaml`. The other two are the locally built image that two steps of `full-weekly.yaml` run.

[SECURITY.md](../SECURITY.md#github-tokens) lists the token permissions of each workflow.

The repository settings that the YAML cannot hold are a checklist in [how-to.md](how-to.md#harden-the-repository-settings), with the reasons in [SECURITY.md](../SECURITY.md#workflows-and-releases).
