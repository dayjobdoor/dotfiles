#!/usr/bin/env bash
# Real lint tasks against stubbed external linters. Run through test:offline: the streamed tree is disposable and has
# no .git, and no linter, network, Docker daemon or repository history is needed.
#
# Contract
#   - lint:secrets uses Git mode whenever .git exists, so a Git error cannot silently reduce the scan to files;
#     a history-free copy still uses directory mode.
#   - lint:config reads mise pins from action steps, not text printed by a run block.
#   - lint:workflows rejects a privileged release-installer token, reads runner labels only from runner settings,
#     and rejects a missing credential ignore pattern or a later negation that re-includes a secret.
#   - lint:shell propagates a file-enumeration error instead of checking a partial list and succeeding.
#   - lint:docs handles duplicate heading anchors, does not treat every http-prefixed path as a URL, and checks
#     path-like spans whose first directory is not in the checkout.
set -euo pipefail

cd "$(dirname "$0")/.."
fail() {
    echo "lint: $1" >&2
    exit 1
}
[ ! -e .git ] || fail "run through test:offline, not in a real checkout"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/secrets-bin"
printf '#!/bin/sh\necho "git repository is not readable" >&2\nexit 128\n' >"$work/secrets-bin/git"
cat >"$work/secrets-bin/gitleaks" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"$GITLEAKS_LOG"
[ "$1" = "$GITLEAKS_ALLOW" ]
EOF
chmod +x "$work/secrets-bin"/*
run_secrets() {
    rc=0
    : >"$work/gitleaks.log"
    env PATH="$work/secrets-bin:/usr/bin:/bin" GITLEAKS_LOG="$work/gitleaks.log" GITLEAKS_ALLOW="$1" \
        bash .mise/tasks/lint/secrets >"$work/out" 2>"$work/err" || rc=$?
}
mkdir .git
run_secrets git
[ "$rc" = 0 ] || fail "a Git error downgraded the history scan: $(cat "$work/err")"
rmdir .git
run_secrets dir
[ "$rc" = 0 ] || fail "a history-free copy did not use directory mode: $(cat "$work/err")"

mkdir "$work/config-bin"
cat >"$work/config-bin/mise" <<'EOF'
#!/bin/sh
if [ "$1" = fmt ]; then cat; fi
exit 0
EOF
chmod +x "$work/config-bin/mise"
run_config() {
    rc=0
    env PATH="$work/config-bin:/usr/bin:/bin" bash .mise/tasks/lint/config >"$work/out" 2>"$work/err" || rc=$?
}
run_config
[ "$rc" = 0 ] || fail "the intact config lint failed: $(cat "$work/err")"
ci=.github/workflows/ci.yaml
cp "$ci" "$work/ci.yaml"
cat >>"$ci" <<'EOF'
      - name: Print action YAML without configuring an action
        run: |
          cat <<'TEXT'
          uses: jdx/mise-action@not-a-pin
          version: latest
          TEXT
EOF
run_config
[ "$rc" = 0 ] || fail "a run block was parsed as a mise action version"
cp "$work/ci.yaml" "$ci"

mkdir "$work/workflow-bin"
for tool in jactionlint hadolint shellcheck; do
    printf '#!/bin/sh\nexit 0\n' >"$work/workflow-bin/$tool"
done
printf '#!/bin/sh\nexit 1\n' >"$work/workflow-bin/docker"
chmod +x "$work/workflow-bin"/*
ignore=.devcontainer/Dockerfile.dockerignore
cp "$ignore" "$work/dockerignore"
run_workflows() {
    rc=0
    env PATH="$work/workflow-bin:/usr/bin:/bin" bash .mise/tasks/lint/workflows >"$work/out" 2>"$work/err" || rc=$?
}
run_workflows
[ "$rc" = 0 ] || fail "the intact workflow lint failed: $(cat "$work/err")"
cat >>"$ci" <<'EOF'
      - name: Print a runner label without selecting a runner
        run: echo ubuntu-24.04
EOF
run_workflows
[ "$rc" = 0 ] || fail "a run command was parsed as a runner label"
cp "$work/ci.yaml" "$ci"
sed -i 's/runs-on: ubuntu-26\.04/runs-on: ubuntu-24.04/' "$ci"
run_workflows
[ "$rc" -ne 0 ] || fail "an unmapped runs-on label was accepted"
cp "$work/ci.yaml" "$ci"
push=.github/workflows/push.yaml
cp "$push" "$work/push.yaml"
sed -i 's/secrets\.DJD_GITHUB_TOKEN/secrets.GITHUB_TOKEN/g' "$push"
run_workflows
[ "$rc" -ne 0 ] || fail "the release installer accepted the job's packages:write token"
cp "$work/push.yaml" "$push"
grep -vxF '**/auth.json' "$work/dockerignore" >"$ignore"
run_workflows
[ "$rc" -ne 0 ] || fail "removing the auth.json ignore pattern was accepted"
cp "$work/dockerignore" "$ignore"
printf '!**/age.txt\n' >>"$ignore"
run_workflows
[ "$rc" -ne 0 ] || fail "a later negation re-included age.txt without failing"
cp "$work/dockerignore" "$ignore"

mkdir "$work/shell-bin"
for tool in shellcheck shfmt; do
    printf '#!/bin/sh\nexit 0\n' >"$work/shell-bin/$tool"
done
printf '#!/bin/sh\nprintf "home/.profile\\0"\necho "find: unreadable directory" >&2\nexit 1\n' >"$work/shell-bin/find"
chmod +x "$work/shell-bin"/*
rc=0
env PATH="$work/shell-bin:/usr/bin:/bin" bash .mise/tasks/lint/shell >"$work/out" 2>"$work/err" || rc=$?
[ "$rc" -ne 0 ] || fail "shell lint ignored a find failure and checked a partial tree"

run_docs() {
    rc=0
    bash .mise/tasks/lint/docs >"$work/out" 2>"$work/err" || rc=$?
}
run_docs
[ "$rc" = 0 ] || fail "the intact docs lint failed: $(cat "$work/err")"
testing=docs/testing.md
cp "$testing" "$work/testing.md"
cat >>"$testing" <<'EOF'

## Test map

[The duplicate heading](testing.md#test-map-1) is a valid GitHub anchor.
EOF
run_docs
[ "$rc" = 0 ] || fail "a duplicate heading's GitHub anchor was rejected: $(cat "$work/err")"
printf '[A third heading does not exist](#test-map-2).\n' >>"$testing"
run_docs
[ "$rc" -ne 0 ] || fail "an anchor beyond the duplicate headings was accepted"
cp "$work/testing.md" "$testing"
printf '[A local path is not a URL](http-file).\n' >>"$testing"
run_docs
[ "$rc" -ne 0 ] || fail "a missing local path beginning with http was ignored"
cp "$work/testing.md" "$testing"
# shellcheck disable=SC2016 # backticks in this fixture are Markdown, not command substitution
printf 'A missing repository path: `definitely-missing/file`.\n' >>"$testing"
run_docs
[ "$rc" -ne 0 ] || fail "a path with an unknown top-level directory was ignored"
cp "$work/testing.md" "$testing"

echo "lint: ok"
