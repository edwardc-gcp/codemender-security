#!/usr/bin/env bash
# Regression tests for cm_remediate_loop.sh with a stub `cm` (no network, no tokens).
# Encodes the Phase 0 finding that `cm fix` resets its workspace: uncommitted work must survive
# and stay visible to the fix through the checkpoint commit.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOOP="${REPO_ROOT}/scripts/cm_remediate_loop.sh"
STUB_DIR="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "${STUB_DIR}" "${WORK}"' EXIT
cp "${REPO_ROOT}/scripts/tests/stub_cm" "${STUB_DIR}/cm"
chmod +x "${STUB_DIR}/cm"
export PATH="${STUB_DIR}:${PATH}"
export GOOGLE_CLOUD_PROJECT="stub-project"

fail() { echo "❌ test_remediate_loop: $*" >&2; exit 1; }

# Repository with one commit, then uncommitted "vibe-coded" work: a tracked edit and an untracked new file.
new_repo() {
  local dir="${WORK}/$1"
  rm -rf "${dir}"
  mkdir -p "${dir}"
  cd "${dir}"
  git init -q
  git config user.email "tester@example.com"
  git config user.name "tester"
  echo "base" > README.md
  printf '*.tmp\n' > .gitignore
  git add README.md .gitignore
  git commit -qm "base"
  BASE_SHA="$(git rev-parse HEAD)"
  echo "user edit" >> README.md
  echo 'query = "UNSAFE"' > app.py
  # State from earlier scans: must never be committed (and must not trip git's ignored-path checks)
  mkdir -p .codemender
  echo "{}" > .codemender/state.json
}

run_loop() {
  if ! bash "${LOOP}" -b true "$@" > "${WORK}/loop.log" 2>&1; then
    cat "${WORK}/loop.log" >&2
    fail "loop exited non-zero ($*)"
  fi
}

assert_user_work_restored() {
  [ "$(git rev-parse HEAD)" = "${BASE_SHA}" ] || fail "$1: HEAD should be back at the original base"
  grep -q "user edit" README.md || fail "$1: tracked user edit was lost"
  git status --porcelain | grep -q '^ M README.md$' || fail "$1: README.md should be an unstaged change"
  git status --porcelain | grep -q '^?? app.py$' || fail "$1: app.py should be untracked again"
  ! git log --format=%s | grep -q "wip(cm)" || fail "$1: checkpoint commit should be gone"
}

# 1. Default: fix applied on top of uncommitted work, which comes back uncommitted.
new_repo default
STUB_FIX_MODE=patch run_loop
assert_user_work_restored "default"
grep -q 'query = "SAFE"' app.py || fail "default: fix was not applied to the uncommitted file"

# 2. cm fix resets its workspace first (Phase 0): nothing is lost and the fix still lands.
new_repo reset
STUB_FIX_MODE=reset-then-patch run_loop
assert_user_work_restored "reset-then-patch"
grep -q 'query = "SAFE"' app.py || fail "reset-then-patch: fix was not applied"

# 3. cm fix fails after a half-applied patch: the partial patch is dropped, user work is intact.
new_repo failure
STUB_FIX_MODE=fail run_loop
assert_user_work_restored "fail"
[ "$(cat app.py)" = 'query = "UNSAFE"' ] || fail "fail: half-applied patch was not dropped"

# 4. --keep-commits keeps the checkpoint and the fix commit.
new_repo keep
STUB_FIX_MODE=patch run_loop --keep-commits
[ "$(git rev-parse HEAD~2)" = "${BASE_SHA}" ] || fail "keep-commits: expected checkpoint + fix commits on top of base"
git log -1 --format=%s | grep -q "security(cm): fix f-001" || fail "keep-commits: missing fix commit"
git log -1 --skip=1 --format=%s | grep -q "wip(cm): checkpoint" || fail "keep-commits: missing checkpoint commit"
[ -z "$(git status --porcelain)" ] || fail "keep-commits: working tree should be clean"
! git ls-files | grep -q '^\.codemender/' || fail "keep-commits: .codemender/ state must never be committed"

# 5. Clean working tree: no checkpoint, the fix is committed on top of HEAD.
new_repo clean
git add -A
git commit -qm "feature"
FEATURE_SHA="$(git rev-parse HEAD)"
STUB_FIX_MODE=patch run_loop
[ "$(git rev-parse HEAD~1)" = "${FEATURE_SHA}" ] || fail "clean: expected exactly one fix commit"
! git log --format=%s | grep -q "wip(cm)" || fail "clean: no checkpoint expected"

# 6. Fix commits contain the patch and new source files only, never CodeMender's ignore edits or stray output.
new_repo artifacts
STUB_FIX_MODE=patch-with-artifacts run_loop --keep-commits
COMMITTED="$(git show --name-only --format= HEAD | sort | tr '\n' ' ')"
[ "${COMMITTED}" = "app.py sanitize.py " ] || fail "artifacts: fix commit should contain only app.py and sanitize.py, got: ${COMMITTED}"
! grep -q '\.exploit' .gitignore || fail "artifacts: .exploit/ edit of .gitignore should have been dropped"
[ ! -e lib/.gitignore ] || fail "artifacts: generated lib/.gitignore should have been removed"
[ ! -e fix.log ] || fail "artifacts: stray fix.log should not survive"

echo "✅ cm_remediate_loop.sh checkpoint and staging tests passed (6 scenarios with stub cm)"
