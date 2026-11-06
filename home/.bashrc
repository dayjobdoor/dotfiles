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
# `command -v tool` below is a path inside the installed tool's own directory. The cache key carries the resolved
# path, and an upgrade that prunes the old version regenerates the script instead of breaking the prompt.
# Not cached: the output of `mise activate` embeds the current PATH. starship keeps the PROMPT_COMMAND it finds
# (STARSHIP_PROMPT_COMMAND), so mise's hook survives starship's init. None of the cached inits changes PATH.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi

# Tool init scripts are cached (omp completions alone cost ~650ms per shell); `djd apply` clears the cache too.
_djd_init() {
    local bin file
    bin=$(command -v "$1") || return 0
    # resolved: mise's `latest` directory stays the same path while the version behind it changes
    bin=$(readlink -f "$bin")
    file="$XDG_CACHE_HOME/bash/init/$1-${bin//[!A-Za-z0-9]/_}.bash"
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
_djd_init starship starship init bash --print-full-init
_djd_init zoxide zoxide init bash
_djd_init omp omp completions bash
if [ -r "$XDG_CONFIG_HOME/djd/bashrc.local" ]; then
    . "$XDG_CONFIG_HOME/djd/bashrc.local"
fi
