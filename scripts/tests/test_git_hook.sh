#!/usr/bin/env bash
# Regression tests for cm_git_hook.sh with a stub `cm` (no network, no tokens).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SCRIPT="${REPO_ROOT}/scripts/cm_git_hook.sh"
SCAN="${REPO_ROOT}/scripts/cm_diff_scan.sh"
STUB_DIR="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "${STUB_DIR}" "${WORK}"' EXIT
cp "${REPO_ROOT}/scripts/tests/stub_cm" "${STUB_DIR}/cm"
chmod +x "${STUB_DIR}/cm"
export PATH="${STUB_DIR}:${PATH}"
export GOOGLE_CLOUD_PROJECT="stub-project"
export STUB_LOG="${WORK}/calls.log"
unset CM_SKIP_HOOK CM_HOOK_STRICT STUB_FIND_MODE

fail() { echo "❌ test_git_hook: $*" >&2; exit 1; }

new_repo() {
  local dir="${WORK}/$1"
  rm -rf "${dir}"
  mkdir -p "${dir}"
  cd "${dir}"
  git init -q
  git config user.email "tester@example.com"
  git config user.name "tester"
  printf 'print("hello")\n' > main.py
  echo "docs" > README.md
  git add main.py README.md
  git commit -qm "base"
  : > "${STUB_LOG}"
}

# Runs a command, storing its exit code in RC and its combined output in OUT.
capture() {
  set +e
  OUT="$("$@" 2>&1)"
  RC=$?
  set -e
}

find_calls() { grep -c '^find ' "${STUB_LOG}" || true; }

# 1. install writes a managed pre-commit hook and copies the runner into the git directory.
new_repo install
capture bash "${HOOK_SCRIPT}" install
[ "${RC}" -eq 0 ] || fail "install: expected exit 0, got ${RC}: ${OUT}"
[ -x .git/hooks/pre-commit ] || fail "install: .git/hooks/pre-commit is missing or not executable"
grep -qF "# codemender-security managed hook" .git/hooks/pre-commit || fail "install: hook marker missing"
for f in cm_git_hook.sh cm_diff_scan.sh cm_exec.sh; do
  [ -x ".git/codemender/${f}" ] || fail "install: runner file ${f} missing"
done
STATUS="$(bash "${HOOK_SCRIPT}" status)"
printf '%s\n' "${STATUS}" | grep -q '^pre-commit: installed (fail on: CRITICAL,HIGH)' || fail "install: status should report the hook: ${STATUS}"

# 2. Blocking findings in the staged changes stop the commit.
echo 'query = "UNSAFE"' > app.py
git add app.py
BASE_SHA="$(git rev-parse HEAD)"
STUB_FIND_MODE=findings capture git commit -qm "add app"
[ "${RC}" -ne 0 ] || fail "blocking: the commit should be blocked"
[ "$(git rev-parse HEAD)" = "${BASE_SHA}" ] || fail "blocking: HEAD should not move"
printf '%s\n' "${OUT}" | grep -q 'CodeMender blocked this commit' || fail "blocking: missing block message: ${OUT}"
grep -q '^find .*--diff --staged' "${STUB_LOG}" || fail "blocking: expected a staged diff scan"

# 3. Retrying the same content reuses the blocking result instead of scanning until a run passes.
: > "${STUB_LOG}"
STUB_FIND_MODE=clean capture git commit -qm "add app"
[ "${RC}" -ne 0 ] || fail "retry: the same staged content should stay blocked"
[ "$(find_calls)" -eq 0 ] || fail "retry: the hook should not scan the same content again"

# 4. Changed content gets a fresh scan, and a clean scan lets the commit through.
echo 'query = "SAFE"' > app.py
git add app.py
STUB_FIND_MODE=clean capture git commit -qm "add app"
[ "${RC}" -eq 0 ] || fail "clean: the commit should succeed: ${OUT}"
[ "$(git rev-parse HEAD)" != "${BASE_SHA}" ] || fail "clean: HEAD should move"

# 5. Commits without source changes skip the scan.
: > "${STUB_LOG}"
echo "more docs" >> README.md
git add README.md
STUB_FIND_MODE=error capture git commit -qm "docs"
[ "${RC}" -eq 0 ] || fail "docs: the commit should succeed: ${OUT}"
[ "$(find_calls)" -eq 0 ] || fail "docs: cm should not be called for non-source changes"

# 6. The hook reuses a manual staged scan of the same content, both clean and blocking.
: > "${STUB_LOG}"
echo 'query = "SAFE 2"' > app.py
git add app.py
STUB_FIND_MODE=clean bash "${SCAN}" --scope staged > /dev/null
STUB_FIND_MODE=error capture git commit -qm "reuse clean"
[ "${RC}" -eq 0 ] || fail "reuse: the commit should reuse the clean result: ${OUT}"
[ "$(find_calls)" -eq 1 ] || fail "reuse: the hook should not scan again"
printf '%s\n' "${OUT}" | grep -q 'already passed a diff scan' || fail "reuse: missing reuse message"
: > "${STUB_LOG}"
echo 'query = "UNSAFE again"' > app.py
git add app.py
STUB_FIND_MODE=findings bash "${SCAN}" --scope staged > /dev/null || true
STUB_FIND_MODE=clean capture git commit -qm "reuse blocking"
[ "${RC}" -ne 0 ] || fail "reuse: the blocking result should be reused"
[ "$(find_calls)" -eq 1 ] || fail "reuse: the hook should not scan again after a blocking result"

# 7. A scan that can't run doesn't block, unless CM_HOOK_STRICT=1; CM_SKIP_HOOK=1 skips the scan.
echo 'query = "UNSAFE 3"' > app.py
git add app.py
STUB_FIND_MODE=error CM_HOOK_STRICT=1 capture git commit -qm "strict"
[ "${RC}" -ne 0 ] || fail "strict: a failed scan should block with CM_HOOK_STRICT=1"
STUB_FIND_MODE=error capture git commit -qm "fail open"
[ "${RC}" -eq 0 ] || fail "fail-open: a failed scan should not block: ${OUT}"
printf '%s\n' "${OUT}" | grep -q 'Not blocking' || fail "fail-open: missing warning"
: > "${STUB_LOG}"
echo 'query = "UNSAFE 4"' > app.py
git add app.py
STUB_FIND_MODE=findings CM_SKIP_HOOK=1 capture git commit -qm "skip"
[ "${RC}" -eq 0 ] || fail "skip: CM_SKIP_HOOK=1 should skip the scan: ${OUT}"
[ "$(find_calls)" -eq 0 ] || fail "skip: cm should not be called"

# 8. uninstall removes the managed hook and the runner.
capture bash "${HOOK_SCRIPT}" uninstall
[ ! -e .git/hooks/pre-commit ] || fail "uninstall: hook should be removed"
[ ! -e .git/codemender ] || fail "uninstall: runner directory should be removed"

# 9. An existing hook that this script didn't write is left unchanged.
new_repo foreign
printf '#!/bin/sh\necho custom\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
capture bash "${HOOK_SCRIPT}" install
[ "${RC}" -eq 0 ] || fail "foreign: expected exit 0, got ${RC}"
[ "$(cat .git/hooks/pre-commit)" = "$(printf '#!/bin/sh\necho custom')" ] || fail "foreign: existing hook was modified"
printf '%s\n' "${OUT}" | grep -q 'codemender/cm_git_hook.sh" run pre-commit' || fail "foreign: missing snippet: ${OUT}"
bash "${HOOK_SCRIPT}" uninstall > /dev/null
[ -e .git/hooks/pre-commit ] || fail "foreign: uninstall must keep a hook it didn't install"

# 10. With core.hooksPath set, no hook file is written.
new_repo hooks_path
git config core.hooksPath .husky
capture bash "${HOOK_SCRIPT}" install
[ "${RC}" -eq 0 ] || fail "hooksPath: expected exit 0, got ${RC}"
[ ! -e .husky/pre-commit ] && [ ! -e .git/hooks/pre-commit ] || fail "hooksPath: no hook file should be written"
printf '%s\n' "${OUT}" | grep -q 'core.hooksPath is set' || fail "hooksPath: missing explanation"

# 11. pre-push scans the pushed branch against the remote branch and blocks on findings.
REMOTE="${WORK}/remote.git"
git init -q --bare "${REMOTE}"
new_repo push
git remote add origin "${REMOTE}"
git push -q -u origin HEAD 2> /dev/null
REMOTE_SHA="$(git rev-parse HEAD)"
bash "${HOOK_SCRIPT}" install --pre-push > /dev/null
[ -x .git/hooks/pre-push ] || fail "pre-push: hook missing"
echo 'query = "UNSAFE"' > app.py
git add app.py
git commit -qm "add app"
: > "${STUB_LOG}"
STUB_FIND_MODE=findings capture git push -q origin HEAD
[ "${RC}" -ne 0 ] || fail "pre-push: the push should be blocked"
[ "$(git --git-dir="${REMOTE}" rev-parse HEAD)" = "${REMOTE_SHA}" ] || fail "pre-push: the remote should not change"
grep -q -- "^find .*--diff=${REMOTE_SHA}" "${STUB_LOG}" || fail "pre-push: expected a diff against the remote branch"
STUB_FIND_MODE=clean capture git push -q origin HEAD
[ "${RC}" -eq 0 ] || fail "pre-push: a clean push should succeed: ${OUT}"

echo "✅ cm_git_hook.sh tests passed (11 scenarios with stub cm: install, block, reuse, fail-open, foreign hooks, pre-push)"
