#!/bin/sh
# Bootstrap these dotfiles on Ubuntu 26.04.
#   curl -fsSL https://raw.githubusercontent.com/dayjobdoor/dotfiles/main/install.sh | sh -s -- [module...]
#   <checkout>/install.sh [module...]
# Modules: agent server desktop full secrets. No modules re-applies the current selection.
set -eu

DJD_REPO="${DJD_REPO:-https://github.com/dayjobdoor/dotfiles.git}"
# must equal mise's dotfiles.root default
DJD_DIR="$HOME/.dotfiles"

die() {
    echo "djd install: $*" >&2
    exit 1
}

# one function called on the last line, so a download cut short by curl runs nothing
main() {
    [ -r /etc/os-release ] && . /etc/os-release
    [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = 26.04 ] ||
        die "Ubuntu 26.04 only (found ${ID:-unknown} ${VERSION_ID:-})"

    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y ca-certificates git curl
    fi

    # from curl | sh, $0 is the shell, not this file
    self=
    if [ -f "$0" ]; then self=$(cd "$(dirname "$0")" && pwd -P); fi
    # a checkout that moved leaves a dangling ~/.dotfiles link behind, which neither ln nor git clone replaces
    if [ -L "$DJD_DIR" ] && [ ! -e "$DJD_DIR" ]; then rm "$DJD_DIR"; fi
    if [ ! -e "$DJD_DIR" ]; then
        if [ -n "$self" ] && [ -f "$self/mise-config/config.toml" ]; then
            ln -s "$self" "$DJD_DIR"
        else
            git clone --depth 1 "$DJD_REPO" "$DJD_DIR"
        fi
    elif [ -n "$self" ] && [ "$(cd "$DJD_DIR" && pwd -P)" != "$self" ]; then
        echo "djd install: applying the existing $DJD_DIR, not $self" >&2
    fi
    [ -f "$DJD_DIR/mise-config/config.toml" ] || die "$DJD_DIR is not a dotfiles checkout"

    cfg="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
    want=$(cd "$DJD_DIR/mise-config" && pwd -P)
    if [ -L "$cfg" ]; then
        [ "$(cd "$cfg" 2>/dev/null && pwd -P)" = "$want" ] || die "$cfg links elsewhere; move it aside first"
    elif [ -d "$cfg" ]; then
        rmdir "$cfg" 2>/dev/null || die "move $cfg aside first"
    elif [ -e "$cfg" ]; then
        die "$cfg is not a directory; move it aside first"
    fi
    if [ ! -e "$cfg" ]; then
        mkdir -p "$(dirname "$cfg")"
        ln -s "$DJD_DIR/mise-config" "$cfg"
    fi

    if [ ! -x "$HOME/.local/bin/mise" ]; then
        # the version the applied tree requires, so the pin has one home; MISE_VERSION overrides it
        version=${MISE_VERSION:-}
        if [ -z "$version" ]; then
            version=$(sed -n 's/^min_version = "\(.*\)"$/v\1/p' "$DJD_DIR/mise-config/config.toml")
            [ -n "$version" ] || die "no min_version in $DJD_DIR/mise-config/config.toml"
        fi
        # sh has no pipefail: a failed download shows up as a missing binary
        curl -fsSL https://mise.run | MISE_VERSION="$version" sh
        [ -x "$HOME/.local/bin/mise" ] || die "installing mise failed"
    fi

    # the wrapper owns the environment that djd tasks need (PATH, LC_ALL, MISE_ENV, cwd)
    if [ $# -gt 0 ]; then
        exec "$DJD_DIR/home/.local/bin/djd" module add "$@"
    fi
    exec "$DJD_DIR/home/.local/bin/djd" apply
}

main "$@"
