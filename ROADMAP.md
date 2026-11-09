# Roadmap

What is planned, by horizon. Nothing here is needed to use or change a machine; [docs/requirements.md](docs/requirements.md) says what ships today, and finished work moves to [CHANGELOG.md](CHANGELOG.md). Short, medium and long term are the maintainer's call and carry no dates; each row names the condition that closes it. Every row is owned by `dayjobdoor`. Releases are not planned here: `tag.yaml` cuts a patch release after every green push run on `main` ([docs/maintenance.md](docs/maintenance.md#release-chain)).

## Short term

- **Raise the mise release from 2026.10.23.** Done when every pin that `guidance.md` lists names the same newer release and `mise run lint:config` passes. 2026.11.3 and later are past the three-day `minimum_release_age`; the steps are in [guidance.md](docs/guidance.md#raise-the-mise-release).
- **Measure what is unmeasured.** Done when [problems.md](docs/problems.md#not-verified) has a number for the start of an interactive zsh with the sheldon plugin set, and for `full-weekly.yaml` after the desktop moved into the base.
- **Try Windows App and mstsc against the TLS-only xrdp.** Done when one of them logs in, or its refusal is recorded in [problems.md](docs/problems.md#rdp-security-and-known-limits).
- **Run the README recipes as written.** Done when the multipass launch with its `chpasswd` block and the incus `passwd` and RDP steps have run once, and their result is in [guidance.md](docs/guidance.md#test-with-multipass).

## Medium term

- **Omarchy-style themes.** Done when changing a token in `DESIGN.md` re-renders the ghostty, starship, XFCE and fzf configs and the Colors table needs no manual sync.
- **`djd menu`.** Done when `djd menu` lists the djd commands with [gum](https://github.com/charmbracelet/gum), has a test, and is in [tech.md](docs/tech.md#djd-commands).
- **An apt install without Recommends and with the few that matter named** (the fcitx5 frontends, `dbus-user-session`, the icon theme, the AT-SPI bridge). Done when the image is about 0.46 GB smaller ([tech.md](docs/tech.md#apt-recommends-stay-on)) and `test:desktop` covers what the Recommends brought.

## Long term

- **A global lock for mise tools,** for machines that must match bit for bit. Done when `lockfile = true` is set in the global config, `mise lock --global` is part of the update flow, and a second machine installs the same versions.
- **A `migrations/` runner** for changes that need imperative steps, in the style of [Omarchy](https://omarchy.org), a Linux setup by DHH. Done when a change that needs an imperative step ships as a migration that `djd apply` runs once.
