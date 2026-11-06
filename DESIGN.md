---
version: alpha
name: Kanagawa Dragon Terminal (Ubuntu)
description: Visual identity of the djd terminal and desktop stack, ported from budybye/dotfiles
omitted:
  - section: rounded
    reason: Terminals and panes have no rounded corners; borders, gaps and padding separate them.
colors:
  primary: "{colors.on-surface}"
  surface: "#112233"
  on-surface: "#D4C69A"
  dragon-black1: "#12120f"
  dragon-black3: "#181616"
  dragon-gray: "#a6a69c"
  dragon-blue2: "#8ba4b0"
  dragon-violet: "#8992a7"
  dragon-aqua: "#8ea4a2"
  dragon-green: "#87a987"
  dragon-orange: "#b6927b"
  dragon-red: "#c4746e"
typography:
  terminal:
    fontFamily: "HackGen35 Console NF"
    fontSize: 13px
spacing:
  window-padding: 8px
components:
  ghostty:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    typography: "{typography.terminal}"
    padding: 8px
  starship-host:
    backgroundColor: "{colors.dragon-gray}"
    textColor: "{colors.dragon-black3}"
  starship-directory:
    backgroundColor: "{colors.dragon-blue2}"
    textColor: "{colors.dragon-black3}"
  starship-git:
    backgroundColor: "{colors.dragon-violet}"
    textColor: "{colors.dragon-black3}"
  starship-runtime:
    backgroundColor: "{colors.dragon-black3}"
    textColor: "{colors.dragon-gray}"
  starship-clock:
    backgroundColor: "{colors.dragon-black1}"
    textColor: "{colors.dragon-gray}"
  starship-duration:
    backgroundColor: "{colors.dragon-black1}"
    textColor: "{colors.dragon-blue2}"
  starship-success:
    textColor: "{colors.dragon-green}"
  starship-error:
    textColor: "{colors.dragon-red}"
  starship-shell:
    textColor: "{colors.dragon-orange}"
  starship-docker:
    textColor: "{colors.dragon-aqua}"
---

# Kanagawa Dragon Terminal (Ubuntu)

## Overview

The stack a person or agent sees on a djd machine. ghostty (installed by the desktop module) runs a login zsh with the starship prompt, and a login zsh on a real terminal starts herdr, which hosts pi/omp panes. The desktop module also installs XFCE and xrdp, but nothing sets ghostty as XFCE's default terminal. The Docker images set `DJD_NO_MUX=1` in the image environment, so a login shell that inherits it (`docker run`, `docker exec`) does not start herdr.

ghostty and the starship prompt use Kanagawa Dragon, and herdr uses its built-in `kanagawa` theme (the Wave palette, a sibling in the same family). ghostty overrides the theme's background and foreground with its own navy background and pale yellow-green text. lazygit, lazydocker, micro and lsd keep their own color settings, and fzf and XFCE have no theme in this repo. The look is dark, low-saturation and low-glare, and depth comes from transparency, never shadows.

## Colors

The front matter holds the Kanagawa Dragon palette that starship uses and ghostty's own background and foreground. Other themed layers name the theme instead of repeating colors. Layers marked not themed keep their own colors.

| Layer | Theme | Source in this repo |
| --- | --- | --- |
| ghostty | Kanagawa Dragon, background `#112233` (surface), foreground `#D4C69A` (on-surface) | `desktop/.config/ghostty/config` |
| starship | `[palettes.color]`, the dragon colors above (its unused `white` is left out) | `home/.config/starship.toml` |
| herdr | built-in `kanagawa` | `home/.config/herdr/config.toml` |
| lazygit, lazydocker | not themed; named ANSI colors (`green`, `blue`, `white`), so they follow the terminal palette | `home/.config/lazygit/config.yml`, `home/.config/lazydocker/config.yaml` |
| micro | not themed; micro's own `default` colorscheme | `home/.config/micro/settings.json` |
| lsd | not themed; its own palette of ANSI names and 256-color numbers | `home/.config/lsd/colors.yaml` |
| fzf, XFCE | not themed; this repo sets no fzf colors and no XFCE theme | none |
| pi / omp | their own dark themes | per-user, not in this repo |

## Typography

One monospace family in ghostty, the only themed terminal: HackGen35 Console NF (Nerd Font patched, Japanese full width at exactly two columns). Ghostty sets 13pt with `font-thicken = true`. TUIs inherit the terminal font. The token says 13px because the spec allows only px, em and rem.

Ubuntu has no HackGen package. The desktop module's module installs the pinned HackGen NF release as the mise tool `http:hackgen` (`mise-config/config.desktop.toml`). mise checks its SHA-256, and the tool's postinstall copies the fonts to `~/.local/share/fonts/HackGen`. Noto CJK covers anything HackGen lacks. Japanese input is fcitx5-mozc.

## Layout

| Item | Value | Source |
| --- | --- | --- |
| ghostty window padding | 8px x/y, balanced | ghostty config |
| herdr sidebar | 28 columns | herdr config `[ui]` |
| herdr pane shell | `zsh`, non-login | herdr config `[terminal]` |
| RDP session | one XFCE session per user, `127.0.0.1:33389` in Docker | `.devcontainer/compose.yaml` |

## Elevation & Depth

Depth is transparency: ghostty `background-opacity = 0.78` lets the XFCE wallpaper sink behind the navy surface. Nothing uses drop shadows. Layers are told apart by borders and gaps.

## Shapes

No rounded corners. herdr draws pane borders and gaps, ghostty balances its window padding, and the cursor is a blinking block that hides the mouse pointer while typing.

## Components

- **ghostty** uses the surface and on-surface colors, the terminal typography and 8px padding.
- **starship** segments run left to right from light to dark: host on dragon-gray, directory on dragon-blue2, a dragon-violet slot (starship's own `git_branch` and `git_status` are disabled), language runtimes on dragon-black3, then clock and command duration on dragon-black1. The git and jj segment comes last on the line, from the `custom.jj` module that runs `jj-starship` (installed by the base module), as dragon-black3 text on dragon-gray. The prompt character is dragon-green after success and dragon-red after an error. The shell indicator is dragon-green, and only the icon after it takes the `starship-shell` token, dragon-orange. The docker context is dragon-aqua. starship's palette names map as gray, navy, dark, dd, ddd, green, red, yellow (dragon-orange) and blue (dragon-aqua).
- **herdr** follows its built-in kanagawa theme and has no color tokens of its own.

## Do's and Don'ts

- Do keep every layer on the Kanagawa family, and add a new tool by its kanagawa theme name before defining colors.
- Do change a color here first, then in the files the Colors table names, so this file stays the source of truth.
- Don't mix unrelated themes across layers or add shadows and rounded corners.
- Don't put machine-specific fonts or colors in the repo; per-user overrides belong in the local files listed in SECURITY.md, but ghostty and herdr read none, so their settings stay the same on every machine.
