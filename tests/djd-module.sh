#!/usr/bin/env bash
# `djd module` list, add and remove, with a stub `mise` that records its calls. Needs bash and coreutils.
# usage: tests/djd-module.sh
#
# Contract
#   - add writes the selection in the canonical order whatever order it arrives in, adds agent with full, and
#     warns about RDP (3389) only when desktop is selected without server.
#   - add warns when secrets and agent are both selected (the selection is still written), and an empty item in
#     MISE_ENV is ignored.
#   - remove of server warns that the hardening is gone.
#   - add and remove run the apply with MISE_ENV unset, because an inherited MISE_ENV outranks the file.
#   - remove writes the new selection before it unapplies, deletes the file when nothing is left, refuses to
#     leave full without agent (exit 2), and unapplies a module even when it was not selected.
#   - A group that was never applied is not an error; any other `mise dot unapply` failure is.
#   - add and remove without a module, or with a word that is no module, exit 2 and write nothing; list reads MISE_ENV and calls nothing.
#
# The task is run as a script with the variables mise's #USAGE parsing would hand it, so the argument choices
# are not covered here. `mise` and `sudo` are stubs on PATH: the real ones would touch the machine.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
task=$here/../mise-config/tasks/djd/module
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

brave=/etc/apt/sources.list.d/mise-brave-browser.sources
stubs=$work/stubs
mkdir "$stubs"
# One line per call: MISE_ENV | arguments | the selection file at that moment
cat >"$stubs/mise" <<'STUB'
#!/bin/sh
printf '%s|%s|%s\n' "${MISE_ENV-unset}" "$*" \
    "$(cat "$HOME/.dotfiles/mise-config/miserc.local.toml" 2>/dev/null || echo none)" >>"$HOME/log"
case "$*" in
"bootstrap unapply"*) exit "${STUB_UNAPPLY_STATUS:-0}" ;;
"dot unapply"*)
    if [ -n "${STUB_DOT_ERROR:-}" ]; then
        echo "$STUB_DOT_ERROR"
        exit 1
    fi
    ;;
esac
STUB
cat >"$stubs/sudo" <<'STUB'
#!/bin/sh
printf 'sudo|%s\n' "$*" >>"$HOME/log"
STUB
chmod +x "$stubs/mise" "$stubs/sudo"
export PATH="$stubs:$PATH"

fail() {
    echo "djd-module: $1" >&2
    exit 1
}

# new_home [group dir...]: a fresh $HOME with an empty mise-config, and the named dotfile group directories
new_home() {
    local g
    HOME=$work/home
    rm -rf "$HOME"
    mkdir -p "$HOME/.dotfiles/mise-config"
    for g in "$@"; do mkdir "$HOME/.dotfiles/$g"; done
    : >"$HOME/log"
    export HOME
}
set_selection() { printf '%s\n' "$1" >"$HOME/.dotfiles/mise-config/miserc.local.toml"; }
# run <MISE_ENV> <action> [module...]: sets rc, $HOME/out, $HOME/err
run() {
    local selected=$1 action=$2
    shift 2
    rc=0
    MISE_ENV=$selected usage_action=$action usage_module="$*" bash "$task" >"$HOME/out" 2>"$HOME/err" || rc=$?
}
want_rc() { [ "$rc" = "$2" ] || fail "$1: exit $rc, want $2: $(cat "$HOME/err")"; }
want_selection() {
    local got=none
    [ ! -e "$HOME/.dotfiles/mise-config/miserc.local.toml" ] || got=$(cat "$HOME/.dotfiles/mise-config/miserc.local.toml")
    [ "$got" = "$2" ] || fail "$1: selection is '$got', want '$2'"
}
want_log() { grep -qxF -- "$2" "$HOME/log" || fail "$1: no call '$2' in: $(cat "$HOME/log")"; }
no_log() {
    if grep -qF -- "$2" "$HOME/log"; then fail "$1: unexpected call '$2' in: $(cat "$HOME/log")"; fi
}
want_err() { grep -q -- "$2" "$HOME/err" || fail "$1: stderr lacks '$2'"; }
no_err() {
    if grep -q -- "$2" "$HOME/err"; then fail "$1: stderr has '$2'"; fi
}

# the canonical order, not the order of arrival, not alphabetical
new_home
run "" add desktop server
want_rc "add desktop server" 0
want_selection "add desktop server" 'env = ["server", "desktop"]'
run desktop add agent
want_rc "add agent to desktop" 0
want_selection "add agent to desktop" 'env = ["agent", "desktop"]'
# an inherited MISE_ENV would outrank the selection file that add just wrote
want_log "apply env" 'unset|run djd:apply|env = ["agent", "desktop"]'

new_home
run "" add full
want_rc "add full" 0
want_selection "add full" 'env = ["agent", "full"]'

# RDP without the firewall rules of server
new_home
run "" add desktop
want_rc "add desktop" 0
want_err "desktop without server" 3389
run "" add desktop server
want_rc "add desktop server" 0
no_err "desktop with server" 3389
run server add desktop
no_err "desktop added to server" 3389

# decrypted secrets next to the agent tools: allowed, with a warning whichever of the two arrives second
new_home
run "" add agent secrets
want_rc "add agent secrets" 0
want_err "add agent secrets" "decrypted values"
want_selection "add agent secrets" 'env = ["agent", "secrets"]'
run secrets add agent
want_rc "add agent to secrets" 0
want_err "add agent to secrets" "decrypted values"
run secrets add full
want_err "add full to secrets" "decrypted values"
new_home
run "" add secrets
want_rc "add secrets alone" 0
no_err "add secrets alone" "decrypted values"
want_selection "add secrets alone" 'env = ["secrets"]'
# an empty item in MISE_ENV is no module
run "server,,secrets" add desktop
want_rc "empty item in MISE_ENV" 0
want_selection "empty item in MISE_ENV" 'env = ["server", "desktop", "secrets"]'

# a word that is no module never reaches the selection (usage's choices stop it first; this is the second line)
new_home
# shellcheck disable=SC2016 # the literal $(...) is the point: it must not run
run "" add 'agent$(touch pwned)'
want_rc "add a bogus module" 2
want_selection "add a bogus module" none
[ ! -e "$HOME/pwned" ] || fail "a module name ran as a command"

# full needs agent; removing both at once is fine
new_home
set_selection 'env = ["agent", "full"]'
run agent,full remove agent
want_rc "remove agent under full" 2
want_selection "remove agent under full" 'env = ["agent", "full"]'
no_log "remove agent under full" unapply
run agent,full remove agent full
want_rc "remove agent and full" 0
want_selection "remove agent and full" none
want_log "remove agent and full" 'unset|run djd:apply|none'

# the selection is written before the unapply, which a failed run relies on to retry
new_home
set_selection 'env = ["server", "desktop"]'
run server,desktop remove desktop
want_rc "remove desktop" 0
want_selection "remove desktop" 'env = ["server"]'
want_log "remove desktop" 'unset|bootstrap unapply desktop --yes|env = ["server"]'
want_log "remove desktop" 'unset|run djd:apply|env = ["server"]'
# removing server takes the hardening away: the remover is told while still logged in
no_err "remove desktop" "sshd may accept passwords"
run server remove server
want_rc "remove server" 0
want_err "remove server" "sshd may accept passwords"
want_err "remove server" "firewall stays enabled"
# a module that is not selected is unapplied anyway: its files may be left over from a run that failed halfway
new_home
set_selection 'env = ["server"]'
run server remove desktop
want_rc "remove unselected desktop" 0
want_selection "remove unselected desktop" 'env = ["server"]'
want_log "remove unselected desktop" 'unset|bootstrap unapply desktop --yes|env = ["server"]'
# a failing unapply stops before the apply
new_home
set_selection 'env = ["server"]'
STUB_UNAPPLY_STATUS=1 run server remove server
[ "$rc" != 0 ] || fail "failed unapply: exit 0"
no_log "failed unapply" "run djd:apply"

# dotfile groups: only a module with a directory is unapplied, and a never applied group is not an error
new_home desktop
set_selection 'env = ["server", "desktop"]'
run server,desktop remove server
want_rc "remove server" 0
no_log "server has no dotfile group" "dot unapply"
STUB_DOT_ERROR="group desktop has no recorded files" run server,desktop remove desktop
want_rc "never applied group" 0
want_log "never applied group" 'unset|dot unapply --group desktop --yes|env = ["server"]'
want_log "never applied group" 'unset|run djd:apply|env = ["server"]'
new_home desktop
STUB_DOT_ERROR="could not read the state" run server,desktop remove desktop
want_rc "failing dot unapply" 1
no_log "failing dot unapply" "run djd:apply"

# no module: nothing is written, nothing is called
new_home
set_selection 'env = ["agent"]'
for action in add remove; do
    run agent "$action"
    want_rc "$action without a module" 2
    want_selection "$action without a module" 'env = ["agent"]'
    [ ! -s "$HOME/log" ] || fail "$action without a module called: $(cat "$HOME/log")"
done

# list reads MISE_ENV and changes nothing
new_home
run server,desktop list
want_rc list 0
printf 'agent -\nserver selected\ndesktop selected\nfull -\nsecrets -\n' >"$HOME/want"
cmp -s "$HOME/out" "$HOME/want" || fail "list prints: $(cat "$HOME/out")"
want_selection list none
[ ! -s "$HOME/log" ] || fail "list called: $(cat "$HOME/log")"

# Brave's apt source outlives mise's unapply and would keep feeding apt upgrade. It sits at a fixed path, so
# this part needs the file to exist (test/offline creates it before this test runs); the VM test covers the real removal.
if [ -e "$brave" ]; then
    new_home
    run desktop remove desktop
    want_rc "remove desktop with Brave's source" 0
    grep -q "^sudo|.*$brave\$" "$HOME/log" || fail "remove desktop left Brave's apt source: $(cat "$HOME/log")"
    new_home
    run server,desktop remove server
    want_rc "remove server with Brave's source" 0
    no_log "remove server with Brave's source" "sudo|"
else
    echo "djd-module: skipped Brave's apt source ($brave is absent)"
fi
echo "djd-module: ok"
