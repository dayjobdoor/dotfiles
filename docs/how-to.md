# How-to guides

Task guides for working on this repository and for the per-machine settings that stay out of it (git identity, npm config). [reference.md](reference.md) and [ci.md](ci.md) hold the facts, and [architecture.md](architecture.md) explains the design.

## Run CI locally

`mise run ci` stops unless `GITHUB_TOKEN` is set: a token without scopes ([GitHub tokens](../SECURITY.md#github-tokens)), or `GITHUB_TOKEN=` (empty) for anonymous downloads. It never falls back to `gh auth token`. `mise run build`, `test` and `test:desktop` stop the same way, and so do their `make` targets. To run every CI job that act supports, run this command on a machine with Docker where you trust the checkout:

```sh
mise run ci
```

To run only some jobs, name them:

```sh
mise run ci lint image
```

To plan every job of `ci.yaml`, `docs.yaml`, `full-weekly.yaml`, `tag.yaml` and `push.yaml` without running any step, add `--dry-run`. It takes no job names:

```sh
mise run ci --dry-run
```

The `vm` job does not run under act. To run it, use `make test:vm` on a machine with incus, multipass, or OrbStack.

## Keep a VM after a failed test

If `make test:vm` fails and you want to inspect the VM, set `DJD_KEEP_VM` to `1`. Any other value, an empty one included, deletes the VM:

```sh
DJD_KEEP_VM=1 make test:vm
```

The VM is named `djd-test-<pid>-<random number>`, and the task prints `vm: <name> is up` once cloud-init has finished. The task waits for cloud-init for at most 900 s. A VM whose cloud-init failed or timed out is never named, so look for it with `incus list`, `multipass list` or `orb list`. When you finish, delete it with `incus delete -f <name>`, `multipass delete --purge <name>`, or `orb delete -f <name>`, depending on the tool that ran.

## Test with multipass and OrbStack

`mise run test:vm` uses the first of incus, multipass and OrbStack that it finds, and feeds the machine the part of `cloud-init/vm.yaml` above `# djd-install-below`. For OrbStack it runs the first two commands of the [README recipe](../README.md#orbstack). The task ran end to end on 2026-11-09 against the working tree, once on OrbStack (arm64, macOS host, about 14 minutes) and once on multipass 1.16.4 (the same host, about 19 minutes): the base (with its desktop) and the server module installed into a fresh `26.04` machine, every check of `tests/vm-checks.sh` passed, and the task deleted the machine again. Two details are specific to multipass on macOS. `multipass exec` spins at 100% CPU forever when its output goes to `/dev/null`, so the task reads the cloud-init wait through a pipe. And `multipass exec` arrives over ssh, so mise refuses to set the firewall to default deny unless `SSH_CONNECTION` survives `sudo`, which `vm_sh` arranges with `--preserve-env`. incus is not covered by a local run; CI runs it. The `curl` install line and the RDP steps of the README recipes are not part of these runs.

## Update a pinned desktop app

Obsidian, Vicinae, Ferdium and HackGen are `http:` tools in `mise-config/config.toml`, pinned to a version and a SHA-256 per platform.

1. Read the new release page and pick the files of both platforms (`linux-x64` and `linux-arm64`). Obsidian's latest release can be mobile-only, so check that it has the Linux archives.
2. Download each file and run `shasum -a 256 <file>`.
3. Change `version` and both `checksum` lines, then run `mise run test:vm` or `mise run test:desktop`.

## Update the pinned tools

To refresh `.mise/mise.lock`, follow these steps on a machine where you trust the checkout.

1. Run `mise lock --bump` with an empty config directory:

   ```sh
   MISE_CONFIG_DIR=$(mktemp -d) mise lock --bump
   ```

   The empty directory keeps the tools of your own global config out of the npm graph in `.mise/.mise/locks/`.

2. Commit `.mise/mise.lock` and the changes under `.mise/.mise/locks/`.

Dependabot covers the pinned actions. It does not cover mise tools.

## Raise the mise release

The mise release is pinned in several files, and no bot bumps them.

1. List the pins:

   ```sh
   grep -nE '^min_version|^ +version: [0-9]' .mise/config.toml mise-config/config.toml .github/workflows/*.yaml
   ```

2. Change every pin to the new release. None has a `v` prefix. `install.sh` has no pin of its own. It reads `min_version` from `mise-config/config.toml` after the checkout is linked, installs that release when mise is missing or older, and adds the `v`. `MISE_VERSION` in the environment overrides the release for one run, but `install.sh` refuses a value older than `min_version`.
3. Run `mise run lint:config`. It fails while two pins differ, and while a file has fewer pins than it should.

## Set your git identity

To set your name and email for commits on one machine, write them to `user.conf`, which the git config includes last, so its values win over the shared ones:

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
3. Run `djd apply`. It moves the regular file aside as `~/.config/starship.toml.djd-backup-<epoch>-<pid>` and links the checkout file again.
4. Delete the backup file when the edit looks right.

## Publish the first release

This repository has released since 0.0.1; the steps below are for a fork or a new copy, whose release chain has not run against GHCR yet, so watch its first run.

1. Run `git init` unless the folder is already a repository, then `git add -A`.
2. Run `git status` and `git ls-files`. Check that neither lists `.devcontainer/.env`, `age.txt`, or `miserc.local.toml`. All three are gitignored.
3. Run `mise trust` in the checkout, then `git config core.hooksPath .githooks`, so that gitleaks runs on each commit, and make the first commit. The hook needs mise and the trust: without them every commit fails.
4. Create the repository on GitHub, add it as `origin`, and enable private vulnerability reporting in its settings. [SECURITY.md](../SECURITY.md#reporting-a-vulnerability) points reporters to it.
5. Push to `main`. CI runs. When it passes, `tag.yaml` creates the tag `0.0.1` and a GitHub release, and `push.yaml` publishes the GHCR image.
6. Read the logs of the jobs that run only on GitHub: the amd64 run of `image`, the incus path of the `vm` job on both architectures, and the merge job of `push.yaml`. A local act run on an arm64 Mac covers only the arm64 run of `image`.
7. From a machine that is not logged in to GHCR, run `docker manifest inspect ghcr.io/<owner>/dotfiles:latest`, where `<owner>` is the lower-case name of your GitHub user or organization. If it fails with `unauthorized`, set the visibility of the `dotfiles` package to public in its GHCR settings.
8. Inspect the image:

   ```sh
   docker buildx imagetools inspect ghcr.io/<owner>/dotfiles:latest
   ```

   Both must list `linux/amd64` and `linux/arm64`, and two attestation entries that show as `unknown/unknown`. Then print the index annotations. The classic `docker manifest inspect` hides them:

   ```sh
   docker buildx imagetools inspect --raw ghcr.io/<owner>/dotfiles:latest | jq .annotations
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
