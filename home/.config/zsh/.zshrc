# Interactive zsh. XDG_* and PATH come from ~/.zshenv -> ~/.profile.

HISTFILE="$XDG_STATE_HOME/zsh/history"
[[ -d ${HISTFILE:h} ]] || mkdir -p ${HISTFILE:h}

export HISTSIZE=123456
export SAVEHIST=123456
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#a6a69c"
export ZLE_REMOVE_SUFFIX_CHARS=$''

setopt share_history
setopt hist_verify
setopt hist_expand
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt auto_param_keys
setopt auto_cd
setopt auto_pushd
setopt auto_param_slash
setopt no_beep
setopt no_flow_control
setopt no_nomatch # an unmatched glob stays literal (curl URLs with ? or [])
setopt correct
setopt mark_dirs
setopt list_types
setopt print_eight_bit
setopt pushd_ignore_dups
setopt prompt_subst
setopt extended_glob

autoload -Uz colors && colors

mkdir -p $XDG_CACHE_HOME/zsh
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
zstyle ':completion:*' use-cache on
# mise first: its hook runs at once and puts the installed tools' own directories before the shims, so
# $commands[tool] resolves inside the tool's directory. Not cached: mise activate output embeds the current PATH.
if (( $+commands[mise] )); then
    eval "$(mise activate zsh)"
fi

# Tool init scripts are cached (omp completions alone cost ~650ms per shell). The file name carries the tool, its
# resolved path (`:A`, so mise's `latest` link counts as the version behind it) and a checksum of the whole command
# line: an upgrade that prunes the old version, or an edited argument below, regenerates the script instead of
# loading a stale one. `djd apply` clears the cache, so a tool that moved without a new path or arguments
# regenerates its script on the next shell.
_djd_init() {
    local file sum
    (( $+commands[$1] )) || return 0
    sum=$(printf '%s\0' "${@:2}" | cksum)
    file=$XDG_CACHE_HOME/zsh/init/$1-${${commands[$1]:A}//[^[:alnum:]]/_}-${sum%% *}.zsh
    if [[ ! -s $file ]]; then
        mkdir -p ${file:h}
        # write aside and rename, so an interrupted or concurrent shell never leaves a partial file
        "${@:2}" >| $file.$$ && mv -f $file.$$ $file || { rm -f $file.$$; return 0 }
    fi
    source $file
}

# Plugins: sheldon prints the commands that source them, pinned in ~/.config/sheldon/plugins.toml and fetched by
# hooks/sheldon-lock. Cached like the tool inits below; `djd apply` clears the cache after a changed pin. It runs before
# compinit, because zsh-completions only adds its directory to fpath and compinit indexes what is there when it runs.
_djd_init sheldon sheldon source

# a dump younger than a day is trusted (compinit -C skips the scan of every fpath file, about 40 ms); a newer zsh
# starts a fresh dump (the version is in the file name)
autoload -Uz compinit
_djd_zcompdump=$XDG_CACHE_HOME/zsh/zcompdump-${ZSH_VERSION}
if [[ -n $_djd_zcompdump(#qN.mh-24) ]]; then
    compinit -C -d $_djd_zcompdump
else
    compinit -d $_djd_zcompdump
fi
unset _djd_zcompdump

zstyle ':completion:*' matcher-list 'm:{:a-z:}={:A-Z:}'
zstyle ':completion:*' format '%B%F{blue}%d%f%b'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:default' menu select=2
# find commands installed since the shell started, without running rehash
zstyle ':completion:*' rehash 1

# not in a subshell: `$(cd dir && pwd)` would capture the listing
chpwd() {
    (( ZSH_SUBSHELL )) || command ls -la
}

[[ $CPUTYPE == x86_64 ]] && export DJD_ARCH=x86_64 # the arch badge of starship.toml
_djd_init starship starship init zsh --print-full-init
_djd_init zoxide zoxide init zsh
_djd_init fzf fzf --zsh
# after fzf: both bind Ctrl-R, and the later one wins
_djd_init atuin atuin init zsh
_djd_init uv uv generate-shell-completion zsh
_djd_init omp omp completions zsh
_djd_init mise mise completion zsh

if [[ -r $ZDOTDIR/.zshrc.local ]]; then
    source $ZDOTDIR/.zshrc.local
fi
