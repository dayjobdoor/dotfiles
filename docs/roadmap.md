# Roadmap

This page lists planned work. You do not need it to use or change a machine. [architecture.md](architecture.md) explains the design.

- A global lock for mise tools, for machines that must match bit for bit: `lockfile = true` in the global config, then `mise lock --global`.
- A `migrations/` runner for changes that need imperative steps, in the style of Omarchy (omarchy.org, a Linux setup by DHH).
- Omarchy-style themes, which switch the colors of many programs at once. The plan renders the tokens of `DESIGN.md` into the ghostty, starship, XFCE, and fzf configs, so the Colors table no longer needs a manual sync.
- `djd menu`, a menu over the djd commands, built with gum (charmbracelet/gum, a tool for menus and prompts in shell scripts).
