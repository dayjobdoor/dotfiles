# Read by every zsh. Keep it to environment only.
# Ubuntu's /etc/zsh/zshrc runs its own compinit, which drops .zcompdump into ZDOTDIR; this skips it. .zshrc runs the one
# compinit of the shell, with a cache path, and keeps mise activate from running another (see there).
skip_global_compinit=1
export ZDOTDIR="${ZDOTDIR:-$HOME/.config/zsh}"
# a missing ~/.profile (a moved checkout leaves the link dangling) must not end every non-interactive zsh: under
# `emulate sh`, a failed `.` exits the shell
if [[ -f $HOME/.profile ]]; then
    emulate sh -c '. "$HOME/.profile"'
fi
typeset -U path PATH
