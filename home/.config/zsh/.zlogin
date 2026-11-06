# `zsh -lc cmd` (agents) also reads this file, and so does `zsh -lic cmd`; the banners would mix into their output
[[ -o interactive && -z ${ZSH_EXECUTION_STRING-} ]] || return

if command -v fortune > /dev/null 2>&1 && \
  command -v cowsay > /dev/null 2>&1; then
    fortune | cowsay
fi

if command -v figlet > /dev/null 2>&1 && \
  command -v lolcat > /dev/null 2>&1; then
    echo "${USER}" | figlet | lolcat
fi
