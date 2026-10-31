# shellcheck shell=sh
# Shared by bash, zsh (via .zshenv) and agentOS guests (which source it explicitly).
# Keep it POSIX and side-effect free: only exports, no mkdir/chmod, no tool calls.

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export DJD_DIR="${DJD_DIR:-$HOME/.dotfiles}"

# mise shims ahead of ~/.local/bin and the system dirs, so non-interactive agent shells see the managed
# tools (each pass prepends, so the last directory listed ends up first)
for dir in "$HOME/.local/bin" "$XDG_DATA_HOME/mise/shims"; do
    case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$dir:$PATH" ;;
    esac
done
unset dir
export PATH

export LANG="${LANG:-C.UTF-8}"
export TZ="${TZ:-Asia/Tokyo}"
export EDITOR="${EDITOR:-vim}"
export LESSHISTFILE="$XDG_STATE_HOME/lesshst"
export PYTHON_HISTORY="$XDG_STATE_HOME/python_history"
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node_repl_history"

# -f, not -r: the agentOS guest shell (brush) reports `[ -r <missing file> ]` as true
if [ -f "$XDG_CONFIG_HOME/djd/profile.local" ]; then
    . "$XDG_CONFIG_HOME/djd/profile.local"
fi
