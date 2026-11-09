# Roadmap

What is planned, by horizon. Nothing here is needed to use or change a machine; [docs/requirements.md](docs/requirements.md) says what ships today, and finished work moves to [CHANGELOG.md](CHANGELOG.md). The horizons are the maintainer's call, and an item moves when its cost or its reason changes.

## Short term

- Raise the mise release from 2026.10.23. 2026.11.3 and later are past the three-day `minimum_release_age`; the pins and the steps are in [guidance.md](docs/guidance.md#raise-the-mise-release).
- Measure the start of an interactive zsh with the sheldon plugin set, and `full-weekly.yaml` after the desktop moved into the base ([problems.md](docs/problems.md#not-verified)).
- Try Windows App and mstsc against the TLS-only xrdp.
- Run the README multipass recipe with its `chpasswd` block, and the incus `passwd` and RDP steps, as written.

## Medium term

- Omarchy-style themes, which switch the colors of many programs at once. The plan renders the tokens of `DESIGN.md` into the ghostty, starship, XFCE and fzf configs, so the Colors table no longer needs a manual sync.
- `djd menu`, a menu over the djd commands, built with [gum](https://github.com/charmbracelet/gum).
- An apt install without Recommends and with the few that matter named (the fcitx5 frontends, `dbus-user-session`, the icon theme, the AT-SPI bridge), for another 0.46 GB ([tech.md](docs/tech.md#apt-recommends-stay-on)). It needs `test:desktop` to cover what the Recommends brought.

## Long term

- A global lock for mise tools, for machines that must match bit for bit: `lockfile = true` in the global config, then `mise lock --global`.
- A `migrations/` runner for changes that need imperative steps, in the style of [Omarchy](https://omarchy.org), a Linux setup by DHH.
