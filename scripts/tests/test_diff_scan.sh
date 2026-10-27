#!/usr/bin/env bash
# Regression tests for cm_diff_scan.sh with a stub `cm` (no network, no tokens).
# Covers the Phase 0 findings: untracked files are invisible to `cm find --diff` unless registered with
# `git add -N`, and exit code 1 means "findings" only when a report was written.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAN="${REPO_ROOT}/scripts/cm_diff_scan.sh"
STUB_DIR="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "${STUB_DIR}" "${WORK}"' EXIT
cp "${REPO_ROOT}/scripts/tests/stub_cm" "${STUB_DIR}/cm"
chmod +x "${STUB_DIR}/cm"
export PATH="${STUB_DIR}:${PATH}"
export GOOGLE_CLOUD_PROJECT="stub-project"
export STUB_LOG="${WORK}/calls.log"
export STUB_DIFF_SNAPSHOT="${WORK}/diff_snapshot.txt"

fail() { echo "❌ test_diff_scan: $*" >&2; exit 1; }

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
  rm -f "${STUB_DIFF_SNAPSHOT}"
}

# Runs the scanner and stores its exit code in RC and its output in OUT.
scan() {
  set +e
  OUT="$(bash "${SCAN}" "$@" 2>&1)"
  RC=$?
  set -e
}

find_call() { grep '^find ' "${STUB_LOG}" || true; }

# 1. Nothing changed: no scan, exit 0.
new_repo clean
scan
[ "${RC}" -eq 0 ] || fail "clean: expected exit 0, got ${RC}: ${OUT}"
[ -z "$(find_call)" ] || fail "clean: cm should not be called"

# 2. Only non-source files changed: skipped without calling cm.
new_repo docs
echo "more docs" >> README.md
scan
[ "${RC}" -eq 0 ] || fail "docs: expected exit 0, got ${RC}"
[ -z "$(find_call)" ] || fail "docs: cm should not be called for non-source changes"
! git status --porcelain | grep -q '\.codemender' || fail "docs: .codemender/ must be ignored via .git/info/exclude"

# 3. Working scope: the untracked new file is visible to git diff during the scan and untracked again afterwards.
new_repo working
echo 'query = "UNSAFE"' > app.py
printf 'print("changed")\n' > main.py
STUB_FIND_MODE=clean scan
[ "${RC}" -eq 0 ] || fail "working: expected exit 0, got ${RC}: ${OUT}"
find_call | grep -q -- '--diff ' || fail "working: expected --diff"
! find_call | grep -q -- '--staged' || fail "working: --staged not expected"
grep -qx 'app.py' "${STUB_DIFF_SNAPSHOT}" || fail "working: untracked app.py was not visible to git diff during the scan"
git status --porcelain | grep -qx '?? app.py' || fail "working: app.py should be untracked again"
[ ! -e .codemender/.diff_scan_intent_to_add ] || fail "working: intent-to-add record should be removed"
[ -f .codemender/last-diff-scan.meta ] || fail "working: meta file missing"

# 4. Blocking findings: exit 1, introduced and legacy findings are reported separately.
STUB_FIND_MODE=findings scan
[ "${RC}" -eq 1 ] || fail "findings: expected exit 1, got ${RC}"
printf '%s\n' "${OUT}" | grep -q 'introduced or affected by this change: 1' || fail "findings: missing introduced summary"
printf '%s\n' "${OUT}" | grep -q 'f-100abc' || fail "findings: missing introduced finding id"
printf '%s\n' "${OUT}" | grep -q 'untouched code (never block): 1' || fail "findings: missing legacy summary"
git status --porcelain | grep -qx '?? app.py' || fail "findings: app.py should be untracked again"

# 5. Tool error without a report: exit 2.
STUB_FIND_MODE=error scan
[ "${RC}" -eq 2 ] || fail "error: expected exit 2, got ${RC}"
git status --porcelain | grep -qx '?? app.py' || fail "error: app.py should be untracked again"

# 6. Staged scope: only staged changes, no intent-to-add.
new_repo staged
printf 'print("staged")\n' > main.py
git add main.py
echo 'query = "UNSAFE"' > app.py
STUB_FIND_MODE=clean scan --scope staged
[ "${RC}" -eq 0 ] || fail "staged: expected exit 0, got ${RC}: ${OUT}"
find_call | grep -q -- '--diff --staged' || fail "staged: expected --diff --staged"
! grep -qx 'app.py' "${STUB_DIFF_SNAPSHOT}" || fail "staged: untracked files must not be registered"

# 7. Auto scope picks staged when only staged changes exist.
new_repo auto_staged
printf 'print("staged")\n' > main.py
git add main.py
STUB_FIND_MODE=clean scan
find_call | grep -q -- '--diff --staged' || fail "auto: expected the staged scope"

# 8. Recovery: an intent-to-add entry left behind by an interrupted run is undone.
new_repo recovery
echo 'query = "UNSAFE"' > app.py
git add -N app.py
mkdir -p .codemender
printf 'app.py\0' > .codemender/.diff_scan_intent_to_add
echo "notes" > notes.txt
scan --scope staged
git status --porcelain | grep -qx '?? app.py' || fail "recovery: leftover intent-to-add entry was not undone"

# 9. last-commit and branch scopes pass the right reference; an empty --fail-on only reports.
new_repo refs
BASE_SHA="$(git rev-parse HEAD)"
printf 'print("feature")\n' > main.py
git commit -qam "feature"
STUB_FIND_MODE=clean scan --scope last-commit --fail-on ""
find_call | grep -q -- '--diff=HEAD~1' || fail "last-commit: expected --diff=HEAD~1"
find_call | grep -q -- '--fail-on= ' || fail "last-commit: expected an empty --fail-on"
: > "${STUB_LOG}"
STUB_FIND_MODE=clean scan --scope branch --base "${BASE_SHA}"
find_call | grep -q -- "--diff=${BASE_SHA}" || fail "branch: expected --diff=<merge base>"

echo "✅ cm_diff_scan.sh tests passed (9 scenarios with stub cm)"
