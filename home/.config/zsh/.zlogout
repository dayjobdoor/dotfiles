# `zsh -lc cmd` (agents) does not read this file, but `zsh -lic cmd` does, so guard like .zlogin.
[[ -o interactive && -z ${ZSH_EXECUTION_STRING-} ]] || return
if command -v fastfetch > /dev/null 2>&1; then
    fastfetch
else
    echo "🍍 🍕 🐈 ♨️ 🍄 🥦 🌈 🚲 🏄 🙏 🌞 🌕 🏴‍☠️"
    echo "( ﾟДﾟ)y─┛~~~~~~~"
fi
