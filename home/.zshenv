# Read by every zsh. Keep it to environment only.
# Ubuntu's /etc/zsh/zshrc runs its own compinit, which drops .zcompdump into ZDOTDIR. .zshrc runs compinit with a cache path.
skip_global_compinit=1
export ZDOTDIR="${ZDOTDIR:-$HOME/.config/zsh}"
emulate sh -c '. "$HOME/.profile"'
typeset -U path PATH
