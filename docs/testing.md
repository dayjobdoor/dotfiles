# Testing reference

What each CI job and each test proves, and where a new test goes. [maintenance.md](maintenance.md) describes the workflows that run them, [architecture.md](architecture.md) explains the decisions, and [guidance.md](guidance.md) has the procedures.

## Jobs in ci.yaml

Every job runs a mise task that you can run locally. `make <task>` runs `mise run <task>`.

### lint

`mise run lint` runs six checks in parallel. Each check installs only its own tools. `lint` has no body of its own. It depends on the six `lint:*` tasks.

- `lint:shell` runs shellcheck and `shfmt -i 4` over every file whose first line is a `sh` or `bash` shebang, plus `home/.profile`, `.bash_profile`, and `.bashrc`, and `zsh -n` on each zsh startup file separately. It does not lint the inline `postinstall` scripts in the TOML files. When `shfmt` finds a difference, it prints `lint: shell is not formatted; run mise run lint:fix`.
- `lint:config` runs `mise fmt` and `mise tasks validate`. It skips the gitignored `*.local.toml` files. It also requires that the `min_version` line of `.mise/config.toml`, the `min_version` line of `mise-config/config.toml`, and every `jdx/mise-action` step (an unquoted `version:` line) name the same mise release, because no bot bumps them. `install.sh` is not a pin, because it reads `min_version`. The check fails and names the source when a pin is missing or reformatted.
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
- Every `tests/*.sh` is named in `docs/directory.md` and is run by a task under `.mise/tasks/`. A bare name inside a quoted or space-delimited list counts as a reference, so a test with a common word for a name could pass trivially.

### The image tests, on amd64 and arm64

The `test` task builds the image and then runs these steps in order. Each step uses a throwaway container of the image, and the test checks exit statuses, not only output.

| # | Step | Must hold |
| --- | --- | --- |
| 1 | Offline tests | `mise run test:offline` passes (see the test map below). |
| 2 | Doctor | `djd doctor` passes and prints an `ok` line for each of `ubuntu` (the OS check), `mise-config`, `login-shell`, `bootstrap`, `dotfiles`, `plugins`, `xrdp-tls`, and `xrdp-root-login`, because a doctor that skipped a check would still exit 0. |
| 3 | Tools on `PATH` | A plain `docker run` finds `rg` without a login shell, and the image holds no `~/.cache/mise/downloads-cas` (a second copy of every tool, 1.2 GB). |
| 4 | `.profile` | `~/.profile` alone puts the shims on `PATH`, tested with `env -i`. |
| 5 | Agent module | A shimmed `node` sees `PI_TELEMETRY=0`, `DO_NOT_TRACK=1`, `PI_CODING_AGENT_DIR` and `OMP_PROFILE` without a login shell. `~/.config/pi/agent/AGENTS.md` and `~/.config/omp/profiles/god/agent/RULES.md` are non-empty links into the checkout's `home/.config/`. |
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
| 16 | Plugins and aliases | An alias that replaces a command is a mise `[shell_alias]` (`cat`, `tree`), and a shortcut (`ll`) is not. sheldon's pinned plugins are in the image, zsh-abbr's submodule zsh-job-queue is checked out, the abbreviations file loads, no `.functions` is left, and an interactive zsh has `zsh-defer`. |

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
| `plugins.toml` newer than `plugins.lock`, a plugin directory removed, or no lock | `FAIL plugins` |
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

### The desktop in the image, on amd64 and arm64

The `test:desktop` task builds the image (a cached build after `test`) and starts a server container, plus a control container of the same image with `security_layer=negotiate` and `AllowRootLogin=true`. The client is an `ubuntu:26.04` container with `freerdp3-x11`, `xvfb`, and `procps`, installed before the clock starts. The first login gets 120 s. The test runs these stages in order.

| # | Stage | Must hold | Why |
| --- | --- | --- | --- |
| 1 | RDP login | An xfreerdp client logs in and XFCE starts through `~/.xsession`. The environment of `xfce4-session`, read as its owner, has `GTK_IM_MODULE=fcitx`, `QT_IM_MODULE=fcitx`, `XMODIFIERS=@im=fcitx`, and `LANG=ja_JP.UTF-8`. | `.xsession` exports the fcitx variables and `LANG=ja_JP.UTF-8`, which has to win over the `LANG=C.UTF-8` of the container and of `/etc/default/locale`. Root cannot read another user's `/proc/PID/environ` in a container, so the owner does. Before the locale moved from `/etc/locale.conf` into `.xsession`, the desktop job of the CI run of 6 November 2026 (commit f111319) passed the same assertion with PAM's value. |
| 2 | TLS key | The fingerprints of the server, the control, and the certificate that the image was built with all differ. | Every container would otherwise share one key, and anyone who pulls the image holds it. |
| 3 | Legacy layer | `xfreerdp3 /sec:rdp`, logged in as a throwaway account `probe`, is refused by the server. Its `xrdp.log` says `requested [RDP], selected []`, no `probe` session starts, and the first session stays up. The control accepts the same client (`selected [RDP]`, and the client stays connected). | Without the control, a client that cannot speak the legacy layer would pass the refusal on any server. The second account shows that a wrongly accepted client would start a session of its own. |
| 4 | Root login | Root gets a password in both containers. The control starts a root `xfce4-session`. The sesman log of the server says `ROOT login attempted, but root login is disabled`, and no root session starts. | The refused client stays at the login screen, so its exit code cannot show a refused root login. |
| 5 | Password secret | The entrypoint sets the password of `dayjobdoor` from `/run/secrets/djd_rdp_password` when no argument gives one, and refuses to start with neither. | `compose.yaml` passes the password as a secret, because an argument shows in `docker inspect` and `/proc/1/cmdline`. The image itself has no password for `ubuntu`, which is the control. |
| 6 | Audio defaults | `pactl get-default-sink` prints `xrdp-sink` and `pactl get-default-source` prints `xrdp-source`. Then the test kills wireplumber, and a new wireplumber process must appear within 30 s with the same two defaults. | This shows that `~/.xsession` started PipeWire and that the autostart entry of `pipewire-module-xrdp` loaded both devices and made them the defaults through `pactl`. The source check matters, because the container has only one sink and wireplumber would pick it without the script. The defaults live in the metadata of wireplumber. The client has no audio device and plays nothing, so the test proves the setup and not the sound. |
| 7 | Apps | `tests/desktop-apps.sh` runs as the desktop user with `DJD_APPS_LAUNCH=1`. For each of brave-browser, ghostty, zen, and zed, the command resolves and prints its version, and the menu entry exists with an `Exec` that resolves. Brave runs that `Exec` line, which carries `--no-sandbox` in the image, plus `--headless=new --dump-dom about:blank`, and the output contains `<html`. Zen runs `--headless --screenshot` and writes a PNG. Ghostty and Zed start inside the RDP session, and each shows a new visible window of its own `WM_CLASS` within 30 s. A window that an earlier launch left does not count. The test logs how long each took. | The VM test runs the same script without the variable. |
| 8 | Supervisor | `tests/xsession-audio.sh` runs as the desktop user. | See the list below the table. |
| 9 | Logout | The test ends `xfce4-session`, which also ends the session bus. No `pipewire`, `pipewire-pulse`, or `wireplumber` of the user remains after 30 s. A second login gets the same two audio defaults from daemons with new PIDs. | Before `~/.xsession` ended what it started, the daemons outlived the logout, and the supervisor started a `wireplumber` against the dead bus. |
| 10 | Container restart | The test restarts the server container, logs in again, and repeats the sink and source checks. | A restart leaves the stale PipeWire socket of the first session in `/run`, and `~/.xsession` must not take it for a live server. The client disconnects first, because it could otherwise reconnect and make the wait pass on its session. |

`tests/xsession-audio.sh` runs the real `~/.xsession` against stub daemons, and the image test runs it too. It took 31 s in an `ubuntu:26.04` container on a Mac (measured once). It checks that:

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

The `test:vm` task starts a fresh Ubuntu 26.04 machine from `cloud-init/vm.yaml` up to its `# djd-install-below` line (the key import and the install below it are left out). In CI that is an incus system container (`images:ubuntu/26.04/cloud`). It pipes `install.sh` into `sh -s -- server`, as the README does, with the tree under test as the clone source. Both the install and `tests/vm-checks.sh` run with `DJD_SKIP_SSH_CHECKS=1`, because the VM has no authorized key, which the server module's `post-packages` hook would otherwise refuse. Then `tests/vm-checks.sh` runs inside it. The script refuses to run unless `DJD_TEST_VM=1`, and exits 2 with a message that names `mise run test:vm`, because it changes the machine: ufw rules, an sshd drop-in, and module removals. Only `test:vm` sets the variable. `test:vm` names the VM `djd-test-<pid>-<random>`, and it waits for cloud-init for at most 900 s (`timeout 900` runs inside the VM). A timeout prints `vm: cloud-init did not finish within 900 s`, and a cloud-init failure prints `vm: cloud-init failed (exit N)` followed by `cloud-init status --long`. The EXIT trap of `tests/vm-checks.sh` removes the test container, its network, and the sshd guard drop-in, so a failed or interrupted run leaves none of them. The checks are:

- `cloud-init/vm.yaml` passes the cloud-init schema check, as a whole.
- `djd doctor` passes, also under a Japanese locale, where a control shows that `ufw` would print its status in Japanese. It reports ok for the sshd and xrdp checks.
- ufw has the expected default policy and rules, with RDP open to private networks only.
- sshd accepts keys only. A drop-in that sorts first with `PasswordAuthentication yes` makes `djd apply` fail and `djd doctor` report `FAIL sshd`. Both succeed again after the file is removed.
- A container published with `-p 80` listens on `127.0.0.1` only, on the default bridge and on a new network.
- `ssh.socket`, avahi-daemon, xrdp, and docker are active.
- The running xrdp started after the last change to `xrdp.ini` and `sesman.ini`, so the hardened settings are in the daemon and not only in the files.
- The user is in the docker group.
- `/etc/default/locale` is `C.UTF-8` and the generated `ja_JP` locale exists.
- The HackGen font is installed, which `fc-list` shows as `HackGen35 Console NF`.
- `mise bootstrap plan --detailed-exitcode` reports no changes.
- `djd module remove server` succeeds. The sshd drop-in and `daemon.json` disappear, the desktop (`~/.xsession`, the Japanese locale) stays, and the ufw SSH rule stays.
- Brave's menu entry carries no `--no-sandbox`. Only the Docker image adds it.

The task uses the first of incus and multipass that it finds. CI installs incus from the Ubuntu archive, initializes it with `incus admin init --minimal`, and opens the daemon socket to every user on the runner (`chmod 666`). It also accepts the `incusbr0` bridge in Docker's `DOCKER-USER` chain, because Docker sets the `FORWARD` policy to `DROP` and would cut the containers off. On a Mac, `make test:vm` runs the same checks with multipass. Both get the checkout through `tests/tree.sh`. The VM is deleted at the end of a run. `DJD_KEEP_VM=1` (exactly `1`) keeps it, to inspect a failure.

[guidance.md](guidance.md#test-with-multipass) records the run of `test:vm` on multipass.

## Test map

| Script | Proves | Run by | Where |
| --- | --- | --- | --- |
| `tests/xsession-audio.sh` | The `~/.xsession` supervisor | `test:offline`, `test:desktop` | The image, the desktop container |
| `tests/djd-module.sh` | `djd module` with a stub `mise`: selection order, the secrets-with-agent warning, empty `MISE_ENV` items, the server-removal warning, the exit 2 and message for a missing or unknown module name, and the removal of Brave's apt source | `test:offline` | The image |
| `tests/server-hooks.sh` | The server `post-packages` hook refuses an apply that would lock the user out of ssh, says why, and leaves the user out of the docker group when it refuses | `test:offline` | The image |
| `tests/tree-check.sh` | What `tests/tree.sh` leaves out of the archive, judged by the repository's own `.gitignore`: it runs in an empty `HOME`, has one canary file for each kind of secret the `.gitignore` covers, nests a git repository and a submodule entry with ignored files inside, and plants a hostile global ignore file and `core.excludesFile` that the archive must not reflect | `test:offline` | The image |
| `tests/desktop-apps.sh` | The four desktop apps, and that Wireshark, Obsidian, Vicinae, Ferdium and fusuma are on `PATH` with a working menu entry | `test:desktop`, `tests/vm-checks.sh` | The image, VM |
| `tests/vm-checks.sh` | The base and server install, including that xrdp runs with the hardened settings | `test:vm` | incus or multipass |
| `tests/tree.sh` | Helper, not a test | `ci`, `test:vm`, `test:offline`, the no-trust flow in AGENTS.md | Host |

The tasks:

| Task | Runs |
| --- | --- |
| `mise run test:offline [test]...` | The offline tests, with no network and no token, on the current tree inside an existing `djd:latest`, with no build. `--image` names another image. |
| `mise run test` | `build`, then `test:offline`, then the steps of the image table above. |
| `mise run test:desktop` | `build`, then the stages of the desktop table above. |
| `mise run test:vm` | The VM test. |
| `mise run lint:docs` | The doc checks, with bash alone. |

`test:offline` streams `tests/tree.sh` into one container per test and prints `== <test>` before each. The containers have no network (`--network none`), so "offline" is enforced, and the tests run on the current tree and not on the copy that the image holds. The run took about 40 s on an existing image in November 2026, with one more test than today, and has not been timed since. `tests/xsession-audio.sh` is the slow test. The names are listed in `.mise/tasks/test/offline`, twice. They are the choices of the `[test]...` argument and the default list in the `read` line. A new offline test needs its name in both places.

Where a new test goes:

| What it checks | Where |
| --- | --- |
| Logic of a djd task or hook, with stubs | `tests/<name>.sh` with a `# Contract` header, listed in `.mise/tasks/test/offline` and named in [directory.md](directory.md#layout) |
| A `djd doctor` check | A `doctor_says` step in `.mise/tasks/test/_default` |
| Something that needs systemd, ufw, sshd, or docker | `tests/vm-checks.sh` |
| Something that needs RDP or X | `.mise/tasks/test/desktop` |

`lint:docs` fails when a `tests/*.sh` is in no task or is not named in `docs/directory.md`.

## Failure output

The test tasks print `FAIL line N: <command>` to stderr when a command fails. With `GITHUB_ACTIONS` set, the ERR traps of `test`, `test:desktop`, `test:vm`, and `tests/vm-checks.sh`, and the `fail()` helper of `test:desktop`, also print `::error::<cause>`. The cause is the line number and the command, with newlines flattened and cut to 300 characters. `gh run view <id>` lists these annotations without the log. `test:vm` passes `GITHUB_ACTIONS` into the VM, so `tests/vm-checks.sh` annotates too.

Two failures do not annotate their cause. A failure inside a container script of `test` annotates the outer `docker run` line, and the inner message stays in the log. The explicit `echo ...; exit 1` failures of `tests/vm-checks.sh` do not trigger the ERR trap, so only their log lines show them.

## Running CI with act

`mise run ci [job...]` runs the jobs `lint` and `image` with [act](https://github.com/nektos/act). Both run by default. The task stops unless `GITHUB_TOKEN` is set, and it checks that before it builds the scratch repository that act runs on. [How to run CI locally](guidance.md#run-ci-locally) shows the commands.

- `.actrc` maps the `ubuntu-26.04` runners to `ghcr.io/catthehacker/ubuntu:act-24.04`, because catthehacker publishes no 26.04 image.
- `mise run ci --dry-run` plans every job of `ci.yaml`, `docs.yaml`, `full-weekly.yaml`, `tag.yaml`, and `push.yaml` without running steps, and it rejects job names. It feeds the release workflows a sample tag push and a sample CI `workflow_run` event.
- act receives a copy of the tracked and unignored files from `tests/tree.sh`, which skips files that are deleted but not yet staged and nested git repositories, and ignores the git configuration and global ignore file of the host. `age.txt`, `miserc.local.toml`, and the `.secrets` file of act never enter its containers.
- Lint fails on any `ubuntu-*` runner label that `.actrc` does not map, because act stops at an interactive image prompt for an unmapped label.

