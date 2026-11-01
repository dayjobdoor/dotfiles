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

if [ -r /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# Tool init scripts are cached (omp completions alone cost ~650ms per shell); `djd apply` clears the cache.
_djd_init() {
    local file="$XDG_CACHE_HOME/bash/init/$1.bash"
    command -v "$1" >/dev/null 2>&1 || return 0
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
_djd_init starship starship init bash --print-full-init
_djd_init zoxide zoxide init bash
_djd_init omp omp completions bash
# mise after starship: `starship init bash` overwrites PROMPT_COMMAND, which would drop mise's hook.
# Not cached: mise's activate output embeds the current PATH.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi

if [ -r "$XDG_CONFIG_HOME/djd/bashrc.local" ]; then
    . "$XDG_CONFIG_HOME/djd/bashrc.local"
fi
