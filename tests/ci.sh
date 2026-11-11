#!/usr/bin/env bash
# The real local-act task with an act stub: no workflow step, Docker container, network or token is used. Run this
# through test:offline, which streams the tree into a disposable container without its .git directory.
#
# Contract
#   - GITHUB_TOKEN= is passed as the explicit empty assignment to all five dry-run calls and to a normal job call;
#     a bare `-s GITHUB_TOKEN` is rejected by the stub just as act rejects it for an empty environment value.
#   - Every scratch repository handed to act has main as its current branch, independently of the host Git config.
set -euo pipefail

cd "$(dirname "$0")/.."
fail() {
    echo "ci: $1" >&2
    exit 1
}
[ ! -e .git ] || fail "run through test:offline, not in a real checkout"

git init -q -b main
git add -A
git -c user.name=test -c user.email=test@localhost commit -qm fixture

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat >"$work/bin/act" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git branch --show-current >>"$ACT_BRANCHES"
while [ "$#" -gt 0 ]; do
    if [ "$1" = -s ]; then
        shift
        [ "$#" -gt 0 ] || exit 2
        printf '%s\n' "$1" >>"$ACT_LOG"
        if [ "$1" = GITHUB_TOKEN ] && [ -z "${GITHUB_TOKEN:-}" ]; then
            echo "Provide value for 'GITHUB_TOKEN':" >&2
            echo "failed to read input: operation not supported by device" >&2
            exit 1
        fi
    fi
    shift
done
EOF
chmod +x "$work/bin/act"

run_ci() {
    local mode=$1 calls=$2
    : >"$work/act.log"
    : >"$work/branches"
    rc=0
    if [ "$mode" = dry-run ]; then
        env PATH="$work/bin:$PATH" ACT_LOG="$work/act.log" ACT_BRANCHES="$work/branches" GITHUB_TOKEN= \
            usage_dry_run=true usage_job= bash .mise/tasks/ci >"$work/out" 2>"$work/err" || rc=$?
    else
        env PATH="$work/bin:$PATH" ACT_LOG="$work/act.log" ACT_BRANCHES="$work/branches" GITHUB_TOKEN= \
            usage_dry_run=false usage_job=lint bash .mise/tasks/ci >"$work/out" 2>"$work/err" || rc=$?
    fi
    [ "$rc" = 0 ] || fail "$mode exited $rc: $(cat "$work/err")"
    [ "$(wc -l <"$work/act.log")" = "$calls" ] || fail "$mode did not make $calls act calls"
    bad=$(grep -v -Fx 'GITHUB_TOKEN=' "$work/act.log" || true)
    [ -z "$bad" ] || fail "$mode passed a non-assignment or non-empty secret: $bad"
    bad=$(grep -v -Fx main "$work/branches" || true)
    [ -z "$bad" ] || fail "$mode ran act on a non-main scratch branch: $bad"
}

run_ci dry-run 5
run_ci normal 1

echo "ci: ok"
