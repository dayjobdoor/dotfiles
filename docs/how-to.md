# How-to guides

Task guides for working on this repository. [reference.md](reference.md) and [ci.md](ci.md) hold the facts, and [architecture.md](architecture.md) explains the design.

## Run CI locally

To run every CI job that act supports, run this command on a machine with Docker where you trust the checkout:

```sh
mise run ci
```

To run only some jobs, name them:

```sh
mise run ci sandbox desktop
```

To plan every job of every workflow without running any step, add `--dry-run`:

```sh
mise run ci --dry-run
```

The `vm` job does not run under act. To run it, use `make test:vm` on a machine with incus, multipass, or OrbStack.

## Keep a VM after a failed test

If `make test:vm` fails and you want to inspect the VM, set `DJD_KEEP_VM`:

```sh
DJD_KEEP_VM=1 make test:vm
```

The VM is named `djd-test-<number>`, and the task prints the name. When you finish, delete it with `incus delete -f <name>`, `multipass delete --purge <name>`, or `orb delete -f <name>`, depending on the tool that ran.

## Try it in an OrbStack machine

```sh
orb create -c cloud-init/vm.yaml ubuntu:resolute djd-vm
orb -m djd-vm -w / sudo cloud-init status --wait   # the install would otherwise race cloud-init's apt run
orb -m djd-vm sh -c 'cd && curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | sh -s -- server desktop'
```

`orb` starts commands in the Mac's current directory, mounted under `/Users`, where mise would also load any Mac `mise.toml` up the tree. The `cd` keeps the install inside the VM home.

For RDP, set a password with `orb -m djd-vm sudo passwd "$USER"`, restart xrdp once with `orb -m djd-vm sudo systemctl restart xrdp xrdp-sesman` (it reads its TLS-only settings at start), and connect to `localhost:3389`. OrbStack forwards the port from loopback, which ufw admits.

The first two commands are the ones `mise run test:vm` runs when it finds OrbStack and no incus. That task ran end to end on OrbStack 2.2.5 (arm64, macOS host) on 2026-11-01 against commit 58eff93. The server and desktop modules installed from `cloud-init/vm.yaml` on `ubuntu:resolute`, every check of `tests/vm-checks.sh` passed, and the task deleted the machine again. The tree has changed since then (`vm-checks.sh` gained a guard and more checks), and no run on the changed tree was recorded when this was written. The `curl` install line and the RDP steps above are not part of that run.

## Update the pinned tools

To refresh `mise.lock`, follow these steps on a machine where you trust the checkout.

1. Run `mise lock --bump` with an empty config directory:

   ```sh
   MISE_CONFIG_DIR=$(mktemp -d) mise lock --bump
   ```

   The empty directory keeps the tools of your own global config out of the npm graph in `.mise/locks/`.

2. Commit `mise.lock` and the changes under `.mise/locks/`.

Dependabot covers the pinned actions and the `agentos-core` package in `agentos/package.json`. It does not cover mise tools.

## Raise the mise release

The mise release is pinned in several files, and no bot bumps them.

1. List the pins:

   ```sh
   grep -nE '^min_version|^ +version: [0-9]' mise.toml mise-config/config.toml .github/workflows/*.yaml
   ```

2. Change every pin to the new release. None has a `v` prefix. `install.sh` has no pin of its own. When mise is missing, it reads `min_version` from `mise-config/config.toml` after the checkout is linked, and adds the `v`. `MISE_VERSION` in the environment overrides that for one run.
3. Run `mise run lint:config`. It fails while two pins differ, and while a file has fewer pins than it should.

## Handle a Dependabot agentos-core pull request

A bump of `@rivet-dev/agentos-core` fails the offline test and the `agentos` job until the lock matches, because `agentos/software.lock.json` records the core version. Dependabot cannot run the lock task, so do this on the pull request branch, on a machine where you trust the checkout.

1. Check out the branch.
2. Run `mise run agentos:lock`. It rewrites `agentos/software.lock.json` from the live release manifest, and it refuses to run while `AGENTOS_SOFTWARE_REGISTRY_URL` is set.
3. Review `git diff agentos/software.lock.json`. The `core` field must equal the version in `agentos/package.json`. Every changed URL and digest is a package that you now install, and nothing compares them with anything else.
4. Run `mise run test:offline agentos-bundle`, which checks the lock and the bundle.
5. Commit the lock file and push it to the pull request branch.

## Set your git identity

To set your name and email for commits on one machine, write them to `user.conf`, which the git config includes:

```sh
git config --file ~/.config/git/user.conf user.name "Your Name"
git config --file ~/.config/git/user.conf user.email "you@example.com"
```

Do not use `git config --global`. It appends to `~/.config/git/config`, which links to a tracked file in the checkout, and it leaves the checkout dirty.

## Move an existing npm config

After the `agent` module sets `NPM_CONFIG_USERCONFIG`, npm no longer reads `~/.npmrc`, and its cache moves to `~/.cache/npm`. On a machine that already has an `~/.npmrc`, move it:

```sh
mkdir -p ~/.config/npm
mv ~/.npmrc ~/.config/npm/npmrc
rm -rf ~/.npm
```

The last command deletes the old cache. bun leaves its old install cache in `~/.bun/install/cache`, and you can delete that directory too. Keep the rest of `~/.bun`: it can hold bun's global packages and a bun that bun.sh installed.

## Keep an edit that a program made

A program that saves a managed file through a rename replaces its link with a regular file. `djd doctor` then reports `differs` for that file. To keep the edit, follow these steps.

1. Copy the file into the checkout. For `~/.config/starship.toml`, run:

   ```sh
   cp ~/.config/starship.toml ~/.dotfiles/home/.config/starship.toml
   ```

2. Run `git -C ~/.dotfiles diff` and check the change.
3. Run `djd apply`. It moves the regular file aside as `~/.config/starship.toml.djd-backup-<time>` and links the checkout file again.
4. Delete the backup file when the edit looks right.

## Publish the first release

Nothing in the release chain has run against GHCR before the first release, so watch the first run.

1. Run `git init` unless the folder is already a repository, then `git add -A`.
2. Run `git status` and `git ls-files`. Check that neither lists `.devcontainer/.env`, `age.txt`, or `miserc.local.toml`. All three are gitignored.
3. Run `mise trust` in the checkout, then `git config core.hooksPath .githooks`, so that gitleaks runs on each commit, and make the first commit. The hook needs mise and the trust: without them every commit fails.
4. Create the repository on GitHub, add it as `origin`, and enable private vulnerability reporting in its settings. [SECURITY.md](../SECURITY.md#reporting-a-vulnerability) points reporters to it.
5. Push to `main`. CI runs. When it passes, `tag.yaml` creates the tag `0.0.1` and a GitHub release, and `push.yaml` publishes the GHCR images.
6. Read the logs of the jobs that run only on GitHub: the amd64 runs of `sandbox` and `desktop`, the incus path of the `vm` job on both architectures, and the merge job of `push.yaml`. A local act run on an arm64 Mac covers only the arm64 runs of `sandbox` and `desktop`.
7. From a machine that is not logged in to GHCR, run `docker manifest inspect ghcr.io/dayjobdoor/dotfiles:sandbox`. If it fails with `unauthorized`, set the visibility of the `dotfiles` package to public in its GHCR settings.
8. Inspect the images:

   ```sh
   docker buildx imagetools inspect ghcr.io/dayjobdoor/dotfiles:sandbox
   docker buildx imagetools inspect ghcr.io/dayjobdoor/dotfiles:desktop
   ```

   Both must list `linux/amd64` and `linux/arm64`, and two attestation entries that show as `unknown/unknown`. Then print the index annotations. The classic `docker manifest inspect` hides them:

   ```sh
   docker buildx imagetools inspect --raw ghcr.io/dayjobdoor/dotfiles:sandbox | jq .annotations
   ```

   The output must hold the description, the MIT license, the source, and the version.
9. Open the package page. It must link to this repository.

## Retry a failed publish

`tag.yaml` creates the release, dispatches `push.yaml` for the tag, and waits for it. When the publish fails, the release exists, no floating tag moved if the smoke test was the cause, and the `tag.yaml` run is red. Re-running `tag.yaml` does not retry the publish. To retry it, follow these steps with the release tag in place of `X.Y.Z`.

1. Run `gh workflow run push.yaml --ref X.Y.Z`.
2. Find the run with `gh run list --workflow push.yaml --limit 1`, then follow it with `gh run watch <id> --exit-status`.

The dispatch shares the concurrency group of `push.yaml` for that tag, so it cancels a tag-push run that is still going. A re-run of CI for a commit that already has a release does not dispatch a publish.

## Harden the repository settings

These settings are not files, so nothing in the repository enforces them, and they are not applied. [SECURITY.md](../SECURITY.md#workflows-and-releases) says why. The steps below were not tested, and GitHub may name the pages differently. The state was read on 2026-11-01 with `gh api repos/dayjobdoor/dotfiles/rulesets` (it returned `[]`) and `gh api repos/dayjobdoor/dotfiles/branches/main` (`"protected": false`). In a fork, use your own owner and name.

- [ ] Add a tag ruleset for the pattern `refs/tags/[0-9]*` that restricts updates and deletions. Do not restrict creations, because `tag.yaml` pushes the tag.
- [ ] Block force pushes and deletions on `main`, with a ruleset or a branch protection rule.
- [ ] In the Actions settings, require actions to be pinned to a full-length commit SHA. Every `uses:` in the workflows is pinned that way, so none should be refused (inference, not tested).
- [ ] Turn on immutable releases. Not tested against the release flow of `tag.yaml`.
- [ ] In the Actions settings, set the default workflow token to read-only. The endpoint for this setting answered 403 to the investigation token, so the current value is unknown.
