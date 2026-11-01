# CI and release reference

Facts about the GitHub Actions workflows, the tests they run, and the release chain. [architecture.md](architecture.md#ci-mirrors-local-tasks-and-releases-are-safe-to-repeat) explains the decisions behind them, and [how-to.md](how-to.md) has the procedures.

## Workflows

| File | Runs on | Does |
| --- | --- | --- |
| `ci.yaml` | Pushes to `main`, pull requests, a weekly schedule, and `workflow_dispatch` | Runs the jobs below. |
| `tag.yaml` | A completed `ci.yaml` run on `main` | Tags and releases a commit that passed. |
| `push.yaml` | A semver tag push, or a dispatch by `tag.yaml` | Publishes the images to GHCR. |
| `full-weekly.yaml` | A weekly schedule and `workflow_dispatch` | Builds the `full` image, runs `djd doctor` in it, then runs `djd update` and `djd doctor` in it. It sits outside the release chain, so a red run never blocks a release. |

`ci.yaml` skips a push or pull request that touches only `docs/**` or Markdown files, except `DESIGN.md`. Such a push also skips the Markdown link check in `lint`. Run `make lint` to check the links, or push a change that touches another file.

The weekly schedule catches upstream breakage, because tools track `latest`. Scheduled runs never release, because `tag.yaml` accepts push runs only. Each event has its own concurrency group, so a scheduled run never cancels the push run that a release waits for.

## Jobs in ci.yaml

Every job runs a mise task that you can run locally. `make <task>` runs `mise run <task>`.

### lint

`mise run lint` runs six checks in parallel. Each check installs only its own tools. `lint` has no body of its own. It depends on the six `lint:*` tasks.

- `lint:shell` runs shellcheck and shfmt over every script, and `zsh -n`.
- `lint:config` runs `mise fmt` and `mise tasks validate`. It also requires that `install.sh`, both `min_version` lines, and every `mise-action` pin name the same mise release, because no bot bumps them.
- `lint:workflows` runs jactionlint over the workflows and `dependabot.yml`, compares the runner labels with `.actrc`, and runs hadolint.
- `lint:design` lints `DESIGN.md`.
- `lint:docs` checks the relative Markdown links and anchors. It also checks that every repo path in an inline code span exists, that every `mise run`, `make`, and `djd` command in a span names a real task or command, and that every `DJD_` variable in the docs appears in the code.
- `lint:secrets` runs gitleaks over the whole git history. When there is no git directory, it runs over the files, so the secret scan never skips.

`lint:fix` rewrites shell and mise TOML formatting.

### sandbox, on amd64 and arm64

The `test` task builds the sandbox image and then checks that:

- `djd doctor` passes.
- Tools are on `PATH` without a login shell.
- `~/.profile` alone puts the shims on `PATH`, tested with `env -i`.
- Interactive zsh and bash start silently on a tty. The first zsh start fetches the pinned sheldon plugins and fills the init caches, so the test drops its output. The second zsh start and a bash start must print nothing.
- `zsh -lc` output contains no `.zlogin` banner.
- One container backs up a conflicting file, relinks a moved checkout through `install.sh`, and converges. Converging means that `djd doctor` and `mise bootstrap plan --detailed-exitcode` both pass.
- A secrets round trip works. The key has mode 600, `djd secret keygen` refuses to overwrite it, the ciphertext lands in `config.secrets.toml` without the plaintext, and the secrets module decrypts the value. `djd doctor` reports the secrets module as ok, then as failed for a missing key, for a different key, and for a key that is not mode 600.

### desktop, on amd64 and arm64

The `test:desktop` task builds the desktop image. An xfreerdp client logs in, and XFCE starts through `~/.xsession`. The task reads the environment of `xfce4-session` as its owner and expects the fcitx variables `GTK_IM_MODULE`, `QT_IM_MODULE`, and `XMODIFIERS`, which `~/.xsession` exports. It checks that `xrdp.ini` says `security_layer=tls` and `sesman.ini` says `AllowRootLogin=false`. A client that forces the legacy layer (`xfreerdp3 /sec:rdp`, logged in as a throwaway account `probe`) must be refused, while the first session stays up. A control server of the same image with `security_layer=negotiate` must keep that client connected, because otherwise a client that cannot speak the legacy layer would pass the refusal on any server. The task then waits for `pactl get-default-sink` to print `xrdp-sink` and for `pactl get-default-source` to print `xrdp-source`. That shows that `~/.xsession` started PipeWire and that the autostart entry of pipewire-module-xrdp loaded both devices and made them the defaults through `pactl`. The source check matters, because the container has only one sink and wireplumber would pick it without the script. The client has no audio device and plays nothing, so the test proves the setup and not the sound. The task then kills wireplumber and expects a new wireplumber process within 30 s and the same two defaults again, because the defaults live in wireplumber's metadata. Then `tests/desktop-apps.sh` runs as the desktop user. For each of brave-browser, ghostty, zen, and zed, the command must resolve and print its version, and the menu entry must exist with an `Exec` that resolves. The image test also sets `DJD_APPS_LAUNCH=1`. Brave then runs the `Exec` line of its menu entry, which carries `--no-sandbox` in the image, plus `--headless=new --dump-dom about:blank`, and the output must contain `<html`. Zen runs `--headless --screenshot` and must write a PNG. Ghostty and Zed start inside the RDP session, and each must show a window of its own `WM_CLASS` within 30 s. The VM test runs the same script without the variable. `tests/xsession-audio.sh` runs as the desktop user too. It runs the real `~/.xsession` against stub daemons and checks that the desktop starts without waiting for a slow server, that wireplumber starts after the server answers and again after it dies, that a wireplumber which keeps dying is given up on after five runs, and that a server which already answers gets nothing started. Last, the task restarts the desktop container, logs in again, and repeats the sink and source checks, because a restart leaves the stale PipeWire socket of the first session in `/run`.

### vm, on amd64 and arm64

The `test:vm` task starts a fresh Ubuntu 26.04 machine from `cloud-init/vm.yaml`. In CI that is an incus system container (`images:ubuntu/26.04/cloud`). It pipes `install.sh` into `sh -s -- server desktop`, as the README does, with the tree under test as the clone source. Then it checks that:

- Both cloud-init files pass the cloud-init schema check.
- `djd doctor` passes, also under a Japanese locale.
- ufw has the expected default policy and rules, with RDP open to private networks only.
- sshd accepts keys only.
- docker binds published ports to `127.0.0.1`.
- `ssh.socket`, avahi-daemon, xrdp, and docker are active.
- The user is in the docker group.
- `/etc/default/locale` and the generated `ja_JP` locale exist.
- The HackGen font is installed.
- `mise bootstrap plan --detailed-exitcode` reports no changes.
- `djd module remove desktop` and `djd module remove server` succeed. The sshd drop-in and `daemon.json` disappear, and the ufw SSH rule stays.

The task uses the first of incus, multipass, and OrbStack (`orb`) that it finds. CI installs incus from the Ubuntu archive, initializes it with `incus admin init --minimal`, and opens the daemon socket to the runner user. It also accepts the `incusbr0` bridge in Docker's `DOCKER-USER` chain, because Docker sets the `FORWARD` policy to `DROP` and would cut the containers off. On a Mac, `make test:vm` runs the same checks with multipass or OrbStack. All three get the checkout through `tests/tree.sh`. `DJD_KEEP_VM=1` keeps the VM after a run.

### agentos

The `agentos:boot` task builds the same bundle that `agentos:export` writes, but in memory, and boots agentOS with it. Before the VM starts, it checks that the bundle holds exactly the allowed files, that none of them is a symlink, a hard link, or a path that resolves outside the repository, that every registry tool is declared in `config.toml` or `config.agent.toml`, and that `AGENTOS_SOFTWARE_REGISTRY_URL` is unset. It also checks that `agentos/software.lock.json` names exactly the `SOFTWARE` packages and the release of the pinned agentos-core, and that the live manifest of that release still matches the lock. The VM then gets the locked URLs and digests, not package names. It runs the `CHECKS` in `boot.mjs`. Sourcing `.profile` must exit 0 with an empty stderr, and the pager, diff filter, and credential helpers of `agentos/gitconfig` must be in effect. The last check fetches api.anthropic.com and must fail with `Could not resolve host`, which shows that the guest network is denied. `agentos:export` runs the offline part of the lock check.

## Repo tasks

Repo tasks are mise file tasks in `mise-tasks/`, plus a few in `mise.toml`. Each task declares its description, its arguments with `#USAGE` and `choices`, its dependencies, and the tools it needs with `tools` or a `#MISE tools=` header. `test` depends on `build sandbox`, so `mise run test` builds what it tests. `mise run agentos:boot` installs node and nothing else. `mise tasks validate` checks the definitions, and the file tasks are plain bash that lint checks like every other script.

`mise.lock` pins tool versions with checksums for the platforms in `lockfile_platforms` in `mise.toml`: `linux-x64`, `linux-arm64`, and `macos-arm64`. `mise lock --bump` moves the pins without installing anything. The npm graph that sits beside the lock is in `.mise/locks/`. `npm.package_manager = "aube"` in `mise.toml` selects it, because the bun of the agent module cannot install a locked aube graph.

The `lint` and `agentos` jobs set `MISE_LOCKED=true`. Their installs use only the URLs and checksums in `mise.lock`, so they call no GitHub API, receive no token, and fail when the lock lacks a tool. `min_version` in `mise.toml` and in `mise-config/config.toml` makes an older mise stop with an error.

In the sandbox image, `mise run lint:shell` from an empty mise data directory installed two tools in 7 s. The whole parallel `lint` took 42 s, including seven tool installs. Both numbers were measured in October 2026 on an arm64 Mac running OrbStack.

## Running CI with act

`mise run ci [job...]` runs the jobs `lint`, `sandbox`, `desktop`, and `agentos` with [act](https://github.com/nektos/act). All four run by default. [How to run CI locally](how-to.md#run-ci-locally) shows the commands.

- `.actrc` maps the `ubuntu-26.04` runners to `ghcr.io/catthehacker/ubuntu:act-24.04`, because catthehacker publishes no 26.04 image.
- `mise run ci --dry-run` plans every job of all four workflows without running steps. It includes the release workflows and feeds them a sample tag push and a sample CI `workflow_run` event.
- act receives a copy of the tracked and unignored files from `tests/tree.sh`, which skips files that are deleted but not yet staged. `age.txt`, `miserc.local.toml`, and the `.secrets` file of act never enter its containers.
- Lint fails on any `ubuntu-*` runner label that `.actrc` does not map, because act stops at an interactive image prompt for an unmapped label.
- The `vm` job needs incus. It runs only on GitHub or through `make test:vm`.

## Release chain

`tag.yaml` runs after a CI run from a push to the `main` branch of this repository passes.

- It releases a commit only when the commit contains the newest `X.Y.Z` tag.
- It bumps the patch number only. A minor or major bump is a manually pushed `X.Y.0` tag. `push.yaml` builds images for that tag and creates no GitHub release.
- It marks a GitHub release `latest` only when its tag is the newest.
- It writes the release notes itself. They list the commits since the previous `X.Y.Z` tag and the `docker pull` commands for both images, because `--generate-notes` lists only pull requests and the pushes to `main` have none.
- It dispatches `push.yaml`, because tags that `GITHUB_TOKEN` pushes start no workflow.

`push.yaml` builds each flavor for each platform with no build cache and pushes by digest. The merge job then creates the multi-arch tags.

| Image | Tags that move with the newest release | Fixed tag |
| --- | --- | --- |
| sandbox | `sandbox`, `latest`, and `X.Y` | `X.Y.Z` |
| desktop | `desktop` and `X.Y-desktop` | `X.Y.Z-desktop` |

A floating tag moves only when the release is the newest `X.Y.Z` tag.

- The merge job writes `description`, `source`, `licenses`, and `version` as index annotations, because GHCR reads the description of a multi-arch package from the index. `docker buildx imagetools create` writes no index annotations unless you pass `--annotation`. A test against a local registry with a docker-container builder confirmed both facts, and the first release confirmed them on GHCR for `sandbox` and `desktop`.
- The images that `push.yaml` builds carry the commit in `DJD_REVISION`, because `.git` is not copied into them.
- GitHub documents private as the default visibility of a new package. The first release of this repository published it as public.

## Workflow audit

jactionlint audits the workflows, and lint runs it.

- Checkouts drop the token with `persist-credentials: false`, except in `tag.yaml`, which pushes the tag.
- Every `uses:` is pinned to a commit.
- Three findings are ignored inline, each with its reason beside it. One is the guarded `workflow_run` trigger in `tag.yaml`. The other two are the locally built image that two steps of `full-weekly.yaml` run.

[SECURITY.md](../SECURITY.md#github-tokens) lists the token permissions of each workflow.
