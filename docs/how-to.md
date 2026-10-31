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

The `vm` job does not run under act. To run it, use `make test:vm` on a machine with LXD or OrbStack.

## Keep a VM after a failed test

If `make test:vm` fails and you want to inspect the VM, set `DJD_KEEP_VM`:

```sh
DJD_KEEP_VM=1 make test:vm
```

The VM is named `djd-test-<number>`, and the task prints the name. When you finish, delete it with `orb delete -f <name>` on a Mac, or with `lxc delete -f <name>` on LXD.

## Update the pinned tools

To refresh `mise.lock`, follow these steps on a machine where you trust the checkout.

1. Run `mise lock --bump` with an empty config directory:

   ```sh
   MISE_CONFIG_DIR=$(mktemp -d) mise lock --bump
   ```

   The empty directory keeps the tools of your own global config out of the npm graph in `.mise/locks/`.

2. Commit `mise.lock` and the changes under `.mise/locks/`.

Dependabot covers the pinned actions and does not cover mise tools.

## Raise the mise release

The mise release is pinned in several files, and no bot bumps them.

1. List the pins:

   ```sh
   grep -nE '^MISE_VERSION|^min_version|^ +version: [0-9]' install.sh mise.toml mise-config/config.toml .github/workflows/*.yaml
   ```

2. Change every pin to the new release. The pin in `install.sh` has a `v` prefix, and the others have none.
3. Run `mise run lint:config`. It fails while two pins differ.

## Set your git identity

To set your name and email for commits on one machine, write them to `user.conf`, which the git config includes:

```sh
git config --file ~/.config/git/user.conf user.name "Your Name"
git config --file ~/.config/git/user.conf user.email "you@example.com"
```

Do not use `git config --global`. It appends to `~/.config/git/config`, which links to a tracked file in the checkout, and it leaves the checkout dirty.

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

1. Run `git init` and `git add -A`.
2. Run `git status` and `git ls-files`. Check that neither lists `.devcontainer/.env`, `age.txt`, or `miserc.local.toml`. All three are gitignored.
3. Run `git config core.hooksPath .githooks`, so that gitleaks runs on each commit.
4. In the repository settings, enable private vulnerability reporting. [SECURITY.md](../SECURITY.md#reporting-a-vulnerability) points reporters to it.
5. Push to `main`. CI runs. When it passes, `tag.yaml` creates the tag `0.0.1` and a GitHub release, and `push.yaml` publishes the GHCR images.
6. Read the logs of the jobs that run only on GitHub: the amd64 runs of `sandbox` and `desktop`, the LXD path of the `vm` job on both architectures, and the merge job of `push.yaml`. A local act run on an arm64 Mac covers only the arm64 runs of `sandbox` and `desktop`.
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
