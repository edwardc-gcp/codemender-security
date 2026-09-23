#!/usr/bin/env bash
# Atomic Non-Destructive Multi-Vulnerability Remediation Loop for CodeMender (cm)
# Safeguards uncommitted work via tracked git stash, enforces outer-shell build hard gates,
# prevents committing $HOME cache artifacts, and reconciles AST line numbers after every commit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CM_EXEC="${SCRIPT_DIR}/cm_exec.sh"

GUIDANCE="Apply minimal security fix preserving existing API behavior"
OUTER_BUILD_CMD=""
TARGET_FIDS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--guidance)
      GUIDANCE="${2:-}"
      shift 2
      ;;
    -b|--build-cmd)
      OUTER_BUILD_CMD="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [-c \"<guidance>\"] [-b \"<outer-build-cmd>\"] [finding_id ...]"
      exit 0
      ;;
    *)
      TARGET_FIDS+=("$1")
      shift
      ;;
  esac
done

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${PROJECT_ROOT}"

# 1. Dynamically probe outer build hard gate if not explicitly provided
if [ -z "${OUTER_BUILD_CMD}" ]; then
  if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || compgen -G "*.py" >/dev/null; then
    if command -v pytest >/dev/null 2>&1 && pytest --collect-only >/dev/null 2>&1; then
      OUTER_BUILD_CMD="pytest"
    else
      OUTER_BUILD_CMD="python3 -m py_compile \$(git ls-files '*.py')"
    fi
  elif [ -f "package.json" ]; then
    OUTER_BUILD_CMD="for f in \$(git ls-files '*.js' '*.mjs' '*.cjs'); do node --check \"\$f\"; done"
  elif [ -f "go.mod" ]; then
    OUTER_BUILD_CMD="go test ./..."
  elif [ -f "Cargo.toml" ]; then
    OUTER_BUILD_CMD="cargo check"
  else
    OUTER_BUILD_CMD="true"
  fi
fi

# 2. Tracked Pre-Fix Stash (P1-4 safe stash lifecycle)
CM_STASH_MSG=""
restore_stash() {
  if [ -n "${CM_STASH_MSG}" ]; then
    local stash_ref
    stash_ref="$(git stash list | grep -F "${CM_STASH_MSG}" | head -n 1 | cut -d: -f1 || true)"
    if [ -n "${stash_ref}" ]; then
      echo "🔄 Restoring tracked stash ${stash_ref} (${CM_STASH_MSG})..."
      git stash pop "${stash_ref}" || echo "⚠️ Merge conflict restoring ${stash_ref}! Your work is safely preserved in: ${stash_ref} (${CM_STASH_MSG})"
    fi
  fi
}
trap restore_stash EXIT

DIRTY_FILES="$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/|\.cache/|\.npm/|\.cargo/|\.local/|\.config/|.*\.sarif$)' || true)"
if [ -n "${DIRTY_FILES}" ]; then
  CM_STASH_MSG="cm-pre-fix-backup-$(date +%s)"
  echo "📌 Saving uncommitted work to tracked git stash: ${CM_STASH_MSG}"
  git stash push -u -m "${CM_STASH_MSG}"
fi

# 3. Resolve actionable findings from `cm report -f json` (Supports jq, python3, or pure awk fallback)
if [ ${#TARGET_FIDS[@]} -eq 0 ]; then
  REPORT_JSON="$("${CM_EXEC}" report -f json 2>/dev/null || true)"
  if command -v jq >/dev/null 2>&1; then
    FINDINGS_RAW="$(printf '%s' "${REPORT_JSON}" | sed -n '/^\[/,$p' | jq -r '.[] | select(.status != "FIXED" and .status != "DISMISSED") | (.finding_id // .id // empty)' 2>/dev/null || true)"
  elif command -v python3 >/dev/null 2>&1; then
    FINDINGS_RAW="$(printf '%s' "${REPORT_JSON}" | python3 -c '
import sys, json
try:
    raw = sys.stdin.read()
    candidates = [i for i in (raw.find("["), raw.find("{")) if i != -1]
    start = min(candidates) if candidates else -1
    data = json.loads(raw[start:]) if start != -1 else []
    items = data if isinstance(data, list) else data.get("findings", [])
    for f in (items if isinstance(items, list) else []):
        if isinstance(f, dict) and f.get("status") not in ("FIXED", "DISMISSED"):
            fid = f.get("finding_id") or f.get("id")
            if fid:
                print(fid)
except Exception as e:
    print(f"⚠️ Warning: failed to parse cm report JSON: {e}", file=sys.stderr)
' || true)"
  else
    # Pure POSIX awk fallback when neither jq nor python3 is installed
    FINDINGS_RAW="$(printf '%s\n' "${REPORT_JSON}" | awk '
      /"finding_id"[[:space:]]*:/ {
        match($0, /"finding_id"[[:space:]]*:[[:space:]]*"[^"]+"/);
        s = substr($0, RSTART, RLENGTH);
        sub(/.*:[[:space:]]*"/, "", s);
        sub(/"$/, "", s);
        fid = s;
      }
      /"status"[[:space:]]*:/ {
        if (fid != "" && $0 !~ /"FIXED"/ && $0 !~ /"DISMISSED"/) {
          print fid;
        }
        fid = "";
      }
    ' || true)"
  fi
  while IFS= read -r fid; do
    [ -z "$fid" ] && continue
    TARGET_FIDS+=("$fid")
  done <<< "${FINDINGS_RAW}"
fi

if [ ${#TARGET_FIDS[@]} -eq 0 ]; then
  echo "✅ No actionable (OPEN / REOPENED) findings to remediate."
  exit 0
fi

# 4. Atomic Remediation Loop (Reconciles AST line numbers after EVERY committed fix)
for fid in "${TARGET_FIDS[@]}"; do
  [ -z "$fid" ] && continue
  echo "🛠️  Remediating finding: ${fid}"
  if "${CM_EXEC}" fix "$fid" -c "${GUIDANCE}" --bypass-warning -y; then
    echo "🧪 Running outer-shell build hard gate: ${OUTER_BUILD_CMD}"
    if ! eval "${OUTER_BUILD_CMD}"; then
      echo "❌ Outer build validation failed for ${fid}! Reverting broken patch..."
      git checkout HEAD -- . && git clean -fd
      continue
    fi
    # Stage code & newly created helper files while strictly excluding HOME cache/runtime artifacts (P0-3)
    git add -A -- \
      ':!.codemender' \
      ':!.cm_project' \
      ':!.exploit' \
      ':!.cache' \
      ':!.npm' \
      ':!.cargo' \
      ':!.local' \
      ':!.config' \
      ':!*.sarif'
    if ! git diff --cached --quiet; then
      git commit -m "security(cm): fix ${fid}"
      echo "✅ Committed verified fix for ${fid}"
      echo "🔍 Reconciling AST line numbers via cm find before next finding..."
      "${CM_EXEC}" find . -y || true
    else
      echo "ℹ️  No file modifications produced for ${fid}."
    fi
  else
    echo "⚠️  cm fix failed for ${fid}; cleaning working tree and continuing..."
    git checkout HEAD -- . && git clean -fd
  fi
done
