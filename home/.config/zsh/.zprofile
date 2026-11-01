# Login shells: start herdr unless already inside herdr (SHLVL, HERDR_ENV), an IDE terminal, a
# non-terminal stdin, or DJD_NO_MUX is set (the Docker images set it).
if [[ -o interactive && -t 0 && $SHLVL == 1 && -z ${DJD_NO_MUX:-} && -z ${HERDR_ENV:-} ]] \
    && [[ ${TERM_PROGRAM:-} != (Cursor|Orca|vscode|herdr|zed) ]] \
    && (( $+commands[herdr] )); then
    herdr
fi
