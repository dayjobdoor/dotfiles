# Login shells: start herdr, through herdr-dev when there is one (it also ensures the dev preset tabs), unless already
# inside herdr (SHLVL, HERDR_ENV), an IDE terminal, a non-terminal stdin, a `-c` command (`zsh -lic cmd`), or DJD_NO_MUX
# is set (the Docker images set it).
if [[ -o interactive && -t 0 && -z ${ZSH_EXECUTION_STRING-} && $SHLVL == 1 && -z ${DJD_NO_MUX:-} && -z ${HERDR_ENV:-} ]] \
    && [[ ${TERM_PROGRAM:-} != (Cursor|Orca|vscode|herdr|zed) ]] \
    && (( $+commands[herdr] )); then
    if (( $+commands[herdr-dev] )); then
        herdr-dev
    else
        herdr
    fi
fi
