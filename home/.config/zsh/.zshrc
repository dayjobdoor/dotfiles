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

# sheldon puts zsh-completions on fpath, and compinit only indexes what is on fpath when it runs, so
# plugins load first. Not cached: its output follows plugins.toml edits (~40ms).
if (( $+commands[sheldon] )); then
    eval "$(sheldon source)"
fi

mkdir -p $XDG_CACHE_HOME/zsh
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
zstyle ':completion:*' use-cache on
autoload -Uz compinit && compinit -d "$XDG_CACHE_HOME/zsh/zcompdump-${ZSH_VERSION}"

zstyle ':completion:*' matcher-list 'm:{:a-z:}={:A-Z:}'
zstyle ':completion:*' format '%B%F{blue}%d%f%b'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:default' menu select=2
# find commands installed since the shell started, without running rehash
zstyle ':completion:*' rehash 1

# not in a subshell: `$(cd dir && pwd)` would capture the listing
chpwd() {
    (( ZSH_SUBSHELL )) || ls -la
}

# Tool init scripts are cached (omp completions alone cost ~650ms per shell).
# `djd apply` clears the cache, so upgraded tools regenerate theirs on the next shell.
_djd_init() {
    local file=$XDG_CACHE_HOME/zsh/init/$1.zsh
    (( $+commands[$1] )) || return 0
    if [[ ! -s $file ]]; then
        mkdir -p ${file:h}
        # write aside and rename, so an interrupted or concurrent shell never leaves a partial file
        "${@:2}" >| $file.$$ && mv -f $file.$$ $file || { rm -f $file.$$; return 0 }
    fi
    source $file
}
_djd_init starship starship init zsh --print-full-init
_djd_init zoxide zoxide init zsh --hook prompt
_djd_init fzf fzf --zsh
# after fzf: both bind Ctrl-R, and the later one wins
_djd_init atuin atuin init zsh
_djd_init uv uv generate-shell-completion zsh
_djd_init omp omp completions zsh
_djd_init mise mise completion zsh
# mise last so its tool paths win (mise doctor: tool paths first). Not cached: its output embeds the
# current PATH, so a cached copy would reset PATH for every later shell.
if (( $+commands[mise] )); then
    eval "$(mise activate zsh)"
fi

if [ -f "${ZDOTDIR}/.functions" ]; then
    . "${ZDOTDIR}/.functions"
fi

if [[ -r $ZDOTDIR/.zshrc.local ]]; then
    source $ZDOTDIR/.zshrc.local
fi
