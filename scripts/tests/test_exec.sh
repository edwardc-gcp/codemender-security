#!/usr/bin/env bash
# Regression tests for cm_exec.sh with a stub `cm` (no network, no tokens).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXEC="${REPO_ROOT}/scripts/cm_exec.sh"
STUB_DIR="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "${STUB_DIR}" "${WORK}"' EXIT
cp "${REPO_ROOT}/scripts/tests/stub_cm" "${STUB_DIR}/cm"
chmod +x "${STUB_DIR}/cm"
export PATH="${STUB_DIR}:${PATH}"
export GOOGLE_CLOUD_PROJECT="stub-project"
export STUB_LOG="${WORK}/calls.log"

fail() { echo "❌ test_exec: $*" >&2; exit 1; }

cd "${WORK}"
git init -q repo
cd repo

# 1. cm init runs when there is no config yet, and never with -y.
: > "${STUB_LOG}"
bash "${EXEC}" init > /dev/null
grep -qx 'init' "${STUB_LOG}" || fail "init: cm init should run without a config"
if bash "${EXEC}" init -y > /dev/null 2>&1; then fail "init -y: should be refused"; fi
mkdir -p .codemender
echo "scan: {}" > .codemender/config.yaml

# 2. With a config, cm init is skipped, but cm init --verify (read-only) still runs.
: > "${STUB_LOG}"
bash "${EXEC}" init > /dev/null
[ ! -s "${STUB_LOG}" ] || fail "init: cm init should be skipped when the config exists"
bash "${EXEC}" init --verify > /dev/null
grep -qx 'init --verify' "${STUB_LOG}" || fail "init --verify: should run when the config exists"

# 3. Runtime paths are protected, and find/verify/fix get the non-interactive display flags.
grep -qxF '.codemender/' .git/info/exclude || fail "exclude: .codemender/ should be registered"
: > "${STUB_LOG}"
bash "${EXEC}" verify f-1 --no-reset -y > /dev/null
grep -qx 'verify f-1 --no-reset -y --bypass-warning --compact' "${STUB_LOG}" || fail "verify: expected --bypass-warning --compact: $(cat "${STUB_LOG}")"

echo "✅ cm_exec.sh tests passed (3 scenarios with stub cm: init guard, init --verify, injected flags)"
