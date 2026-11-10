#!/usr/bin/env bash
# `djd module` list, add and remove, with a stub `mise` that records its calls. Needs bash and coreutils.
# usage: tests/djd-module.sh
#
# Contract
#   - add writes the selection in the canonical order whatever order it arrives in, adds agent with full, and
#     warns about RDP (3389) whenever server is not selected (every machine has xrdp; only server adds the firewall).
#   - add warns when secrets and agent are both selected (the selection is still written), and an empty item in
#     MISE_ENV is ignored.
#   - remove of server warns that the hardening is gone.
#   - add and remove run the apply with MISE_ENV unset, because an inherited MISE_ENV outranks the file.
#   - remove writes the new selection before it unapplies, deletes the file when nothing is left, refuses to
#     leave full without agent (exit 2), and unapplies a module even when it was not selected.
#   - add and remove without a module, or with a word that is no module, exit 2 and say why ("name at least one
#     module", "unknown module") and write nothing; list reads MISE_ENV and calls nothing.
#
# The task is run as a script with the variables mise's #USAGE parsing would hand it, so the argument choices
# are not covered here. `mise` and `sudo` are stubs on PATH: the real ones would touch the machine.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
task=$here/../mise-config/tasks/djd/module
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

stubs=$work/stubs
mkdir "$stubs"
# One line per call: MISE_ENV | arguments | the selection file at that moment
cat >"$stubs/mise" <<'STUB'
#!/bin/sh
printf '%s|%s|%s\n' "${MISE_ENV-unset}" "$*" \
    "$(cat "$HOME/.dotfiles/mise-config/miserc.local.toml" 2>/dev/null || echo none)" >>"$HOME/log"
case "$*" in
"bootstrap unapply"*) exit "${STUB_UNAPPLY_STATUS:-0}" ;;
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

# new_home: a fresh $HOME with an empty mise-config
new_home() {
    HOME=$work/home
    rm -rf "$HOME"
    mkdir -p "$HOME/.dotfiles/mise-config"
    : >"$HOME/log"
    export HOME
}
set_selection() { printf '%s\n' "$1" >"$HOME/.dotfiles/mise-config/miserc.local.toml"; }
# run <MISE_ENV> <action> [module...]: sets rc, $HOME/out, $HOME/err. The task runs in $HOME, so a file that a word
# makes it create lands where the injection check looks.
run() {
    local selected=$1 action=$2
    shift 2
    rc=0
    (cd "$HOME" && MISE_ENV=$selected usage_action=$action usage_module="$*" bash "$task") >"$HOME/out" 2>"$HOME/err" || rc=$?
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
run "" add secrets server
want_rc "add secrets server" 0
want_selection "add secrets server" 'env = ["server", "secrets"]'
run server,secrets add agent
want_rc "add agent to server" 0
want_selection "add agent to server" 'env = ["agent", "server", "secrets"]'
# an inherited MISE_ENV would outrank the selection file that add just wrote
want_log "apply env" 'unset|run djd:apply|env = ["agent", "server", "secrets"]'

new_home
run "" add full
want_rc "add full" 0
want_selection "add full" 'env = ["agent", "full"]'

# RDP without the firewall rules of server: every machine has xrdp
new_home
run "" add agent
want_rc "add agent" 0
want_err "agent without server" 3389
run "" add agent server
want_rc "add agent server" 0
no_err "agent with server" 3389
run server add agent
no_err "agent added to server" 3389

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
run "server,,secrets" add agent
want_rc "empty item in MISE_ENV" 0
want_selection "empty item in MISE_ENV" 'env = ["agent", "server", "secrets"]'

# a word that is no module never reaches the selection (usage's choices stop it first; this is the second line). The
# word has no space, so the task sees one word, and it would create $HOME/pwned if anything evaluated it.
# shellcheck disable=SC2016 # the literal $(...) is the point: it must not run
bogus='agent$(touch${IFS}pwned)'
new_home
run "" add "$bogus"
want_rc "add a bogus module" 2
want_err "add a bogus module" "unknown module"
want_selection "add a bogus module" none
[ ! -s "$HOME/log" ] || fail "add a bogus module called: $(cat "$HOME/log")"
[ ! -e "$HOME/pwned" ] || fail "a module name ran as a command"
# remove refuses the same way, before it unapplies the valid word in front of the bad one
new_home
set_selection 'env = ["agent", "server"]'
run agent,server remove server "$bogus"
want_rc "remove a bogus module" 2
want_err "remove a bogus module" "unknown module"
want_selection "remove a bogus module" 'env = ["agent", "server"]'
[ ! -s "$HOME/log" ] || fail "remove a bogus module called: $(cat "$HOME/log")"
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
set_selection 'env = ["agent", "server", "full"]'
run agent,server,full remove full
want_rc "remove full" 0
want_selection "remove full" 'env = ["agent", "server"]'
want_log "remove full" 'unset|bootstrap unapply full --yes|env = ["agent", "server"]'
want_log "remove full" 'unset|run djd:apply|env = ["agent", "server"]'
# removing server takes the hardening away: the remover is told while still logged in
no_err "remove full" "sshd may accept passwords"
run server remove server
want_rc "remove server" 0
want_err "remove server" "sshd may accept passwords"
want_err "remove server" "firewall stays enabled"
# a module that is not selected is unapplied anyway: its files may be left over from a run that failed halfway
new_home
set_selection 'env = ["server"]'
run server remove secrets
want_rc "remove unselected secrets" 0
want_selection "remove unselected secrets" 'env = ["server"]'
want_log "remove unselected secrets" 'unset|bootstrap unapply secrets --yes|env = ["server"]'
# a failing unapply stops before the apply
new_home
set_selection 'env = ["server"]'
STUB_UNAPPLY_STATUS=1 run server remove server
[ "$rc" != 0 ] || fail "failed unapply: exit 0"
no_log "failed unapply" "run djd:apply"

# no module: nothing is written, nothing is called
new_home
set_selection 'env = ["agent"]'
for action in add remove; do
    run agent "$action"
    want_rc "$action without a module" 2
    want_err "$action without a module" "name at least one module"
    want_selection "$action without a module" 'env = ["agent"]'
    [ ! -s "$HOME/log" ] || fail "$action without a module called: $(cat "$HOME/log")"
done

# list reads MISE_ENV and changes nothing
new_home
run server,full list
want_rc list 0
printf 'agent -\nserver selected\nfull selected\nsecrets -\n' >"$HOME/want"
cmp -s "$HOME/out" "$HOME/want" || fail "list prints: $(cat "$HOME/out")"
want_selection list none
[ ! -s "$HOME/log" ] || fail "list called: $(cat "$HOME/log")"

echo "djd-module: ok"
