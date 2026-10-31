# zsh reads $ZDOTDIR/.zshenv, not ~/.zshenv, once ZDOTDIR is exported (every nested zsh: herdr panes,
# terminals in the desktop session, `zsh -c` from scripts). Delegate so they all load ~/.profile.
source "$HOME/.zshenv"
