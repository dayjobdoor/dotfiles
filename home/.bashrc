# shellcheck shell=bash
case $- in
*i*) ;;
*) return ;;
esac

# a non-login shell (a terminal started from a desktop session) has not read .profile yet
if [ -z "${DJD_DIR:-}" ] && [ -r "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

HISTFILE="$XDG_STATE_HOME/bash/history"
mkdir -p "${HISTFILE%/*}"
HISTSIZE=100000
HISTFILESIZE=100000
HISTCONTROL=ignorespace
HISTTIMEFORMAT='%F %T '
shopt -s histappend

# a login shell has sourced it already through /etc/profile.d (BASH_COMPLETION_VERSINFO is set then)
if [ -z "${BASH_COMPLETION_VERSINFO:-}" ] && [ -r /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# mise first: its hook runs at once and puts the installed tools' own directories before the shims, so
# `command -v tool` resolves inside the tool's directory. Not cached: mise activate output embeds the current PATH.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi

# Tool init scripts are cached (omp completions alone cost ~650ms per shell). The file name carries the tool, its
# resolved path and the whole command line: an upgrade that prunes the old version, or an edited
# argument below, regenerates the script instead of loading a stale one. `djd apply` clears the cache, so a tool
# that moved without a new path or arguments regenerates its script on the next shell.
_djd_init() {
    local bin file sum
    bin=$(command -v "$1") || return 0
    # resolved: mise's `latest` directory stays the same path while the version behind it changes
    bin=$(readlink -f "$bin")
    sum="${*:2}"
    sum=${sum//[!A-Za-z0-9]/_} # the command line itself, no fork for a checksum
    file="$XDG_CACHE_HOME/bash/init/$1-${bin//[!A-Za-z0-9]/_}-$sum.bash"
    if [ ! -s "$file" ]; then
        mkdir -p "${file%/*}"
        # write aside and rename, so an interrupted or concurrent shell never leaves a partial file
        if "${@:2}" >"$file.$$"; then
            mv -f "$file.$$" "$file"
        else
            rm -f "$file.$$"
            return 0
        fi
    fi
    # shellcheck source=/dev/null
    . "$file"
}
PS1='\[\e[32m\]\u@\h\[\e[m\]:\[\e[34m\]\w\[\e[m\] \$ '
[ "$HOSTTYPE" = x86_64 ] && export DJD_ARCH=x86_64 # the arch badge of starship.toml
# starship keeps the PROMPT_COMMAND it finds (STARSHIP_PROMPT_COMMAND), so mise's hook survives starship's init
_djd_init starship starship init bash --print-full-init
_djd_init zoxide zoxide init bash
_djd_init omp omp completions bash
if [ -r "$XDG_CONFIG_HOME/djd/bashrc.local" ]; then
    . "$XDG_CONFIG_HOME/djd/bashrc.local"
fi
