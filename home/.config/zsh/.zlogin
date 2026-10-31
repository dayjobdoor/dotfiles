# `zsh -lc cmd` (agents) also reads this file; its output would mix into theirs
[[ -o interactive ]] || return

if command -v fortune > /dev/null 2>&1 && \
  command -v cowsay > /dev/null 2>&1; then
    fortune | cowsay
fi

if command -v figlet > /dev/null 2>&1 && \
  command -v lolcat > /dev/null 2>&1; then
    echo "${USER}" | figlet | lolcat
fi
