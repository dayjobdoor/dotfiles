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

# whether version $2 (empty counts as 0) is at least $1
at_least() {
    [ "$(printf '%s\n%s\n' "$1" "${2:-0}" | sort -V | sed -n 1p)" = "$1" ]
}

mise_version() {
    "$HOME/.local/bin/mise" --version 2>/dev/null | awk '{ print $1; exit }'
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
    case ${0##*/} in
    install.sh) if [ -f "$0" ]; then self=$(cd "$(dirname "$0")" && pwd -P); fi ;;
    esac
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

    # the version the applied tree requires, so the pin has one home; MISE_VERSION overrides it (with or without
    # the leading v), but never below that minimum
    min=$(sed -n 's/^min_version = "\(.*\)"$/\1/p' "$DJD_DIR/mise-config/config.toml")
    [ -n "$min" ] || die "no min_version in $DJD_DIR/mise-config/config.toml"
    version=${MISE_VERSION:-$min}
    version=v${version#v}
    at_least "$min" "${version#v}" || die "MISE_VERSION $version is older than the required $min"
    # an install that predates min_version would make every `djd apply` fail on it, so it is replaced as well
    install_mise=
    if [ ! -x "$HOME/.local/bin/mise" ]; then
        install_mise=1
    else
        at_least "$min" "$(mise_version)" || install_mise=1
    fi
    if [ -n "$install_mise" ]; then
        # a file, not a pipe into sh: a download cut short must not run; TLS 1.2 or newer, https only
        mise_sh=$(mktemp)
        trap 'rm -f "$mise_sh"' EXIT
        curl -fsSL --proto '=https' --tlsv1.2 https://mise.run -o "$mise_sh" || die "downloading mise.run failed"
        MISE_VERSION="$version" sh "$mise_sh"
        rm -f "$mise_sh"
        # a failed install leaves a missing binary, or the old one that was there before
        [ -x "$HOME/.local/bin/mise" ] || die "installing mise failed"
        have=$(mise_version)
        at_least "$min" "$have" || die "installing mise failed: ${have:-no version} is older than the required $min"
    fi

    # the wrapper owns the environment that djd tasks need (PATH, LC_ALL, MISE_ENV, cwd)
    if [ $# -gt 0 ]; then
        exec "$DJD_DIR/home/.local/bin/djd" module add "$@"
    fi
    exec "$DJD_DIR/home/.local/bin/djd" apply
}

main "$@"
