# Login shells: start herdr unless already inside a multiplexer or an IDE terminal.
if [[ -o interactive && -t 0 && $SHLVL == 1 && -z ${DJD_NO_MUX:-} && -z ${HERDR_ENV:-} ]] \
    && [[ ${TERM_PROGRAM:-} != (Cursor|Orca|vscode|herdr|zed) ]] \
    && (( $+commands[herdr] )); then
    herdr
fi
