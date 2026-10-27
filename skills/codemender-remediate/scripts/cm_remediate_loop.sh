#!/usr/bin/env bash
# Atomic Non-Destructive Multi-Vulnerability Remediation Loop for CodeMender (cm)
# Protects uncommitted work with a checkpoint commit, enforces outer-shell build hard gates, commits fixes the way the
# official autofix job does, and re-scans the change with cm_diff_scan.sh after every fix.
#
# Usage: cm_remediate_loop.sh [-c "<guidance>"] [-b "<outer-build-cmd>"] [--keep-commits] [--strict]
#                             [--base REF] [--max-fixes N] [--fail-on SEVERITIES] [--all-open | finding_id ...]
#   (default)       fix the findings introduced by the current change (uncommitted work, else the branch vs --base or
#                   its upstream), re-scanning after every fix
#   finding_id ...  fix exactly these findings; each fix commit is scanned for new blocking findings
#   --all-open      fix OPEN / REOPENED findings from the local state database (for example from an earlier full scan)
#   --strict        revert a fix commit when the re-scan still reports the target or finds new findings
#   --keep-commits  keep the checkpoint and fix commits instead of restoring uncommitted changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CM_EXEC="${SCRIPT_DIR}/cm_exec.sh"

GUIDANCE="Apply minimal security fix preserving existing API behavior"
OUTER_BUILD_CMD=""
KEEP_COMMITS=false
STRICT=false
ALL_OPEN=false
BASE_REF=""
MAX_FIXES=10
FAIL_ON="CRITICAL,HIGH"
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
    --keep-commits)
      KEEP_COMMITS=true
      shift
      ;;
    --strict)
      STRICT=true
      shift
      ;;
    --all-open)
      ALL_OPEN=true
      shift
      ;;
    --base)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --max-fixes)
      MAX_FIXES="${2:-10}"
      shift 2
      ;;
    --fail-on)
      FAIL_ON="${2-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed -E 's/^# ?//'
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

# 1. Strategy Pipeline for polyglot outer build hard gate detection
probe_config_file() {
  [ -f ".codemender/config.yaml" ] && sed -n 's/^[[:space:]]*command:[[:space:]]*["'"'"']\(.*\)["'"'"'][[:space:]]*$/\1/p' .codemender/config.yaml | head -n 1
}

probe_node() {
  [ -f "package.json" ] || return 1
  [ -f "tsconfig.json" ] && command -v npx >/dev/null 2>&1 && echo "npx tsc --noEmit" && return 0
  grep -q '"test":' package.json 2>/dev/null && [ -d "node_modules" ] && echo "npm test" && return 0
  echo "for f in \$(git ls-files '*.js' '*.mjs' '*.cjs'); do node --check \"\$f\"; done"
}

probe_python() {
  { [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || compgen -G "*.py" >/dev/null; } || return 1
  command -v pytest >/dev/null 2>&1 && pytest --collect-only >/dev/null 2>&1 && echo "pytest" && return 0
  echo "python3 -m py_compile \$(git ls-files '*.py')"
}

probe_golang() {
  [ -f "go.mod" ] && echo "go test ./..."
}

probe_rust() {
  [ -f "Cargo.toml" ] && echo "cargo check"
}

probe_jvm() {
  [ -f "pom.xml" ] && echo "mvn test-compile -q" && return 0
  { [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; } && echo "./gradlew testClasses --quiet" && return 0
  return 1
}

detect_outer_build_cmd() {
  local probers=(probe_config_file probe_node probe_python probe_golang probe_rust probe_jvm)
  for prober in "${probers[@]}"; do
    local detected_cmd
    if detected_cmd="$($prober 2>/dev/null)" && [ -n "${detected_cmd}" ]; then
      echo "${detected_cmd}"
      return 0
    fi
  done
  echo "true"
}

OUTER_BUILD_CMD="${OUTER_BUILD_CMD:-$(detect_outer_build_cmd)}"

# 2. Checkpoint commit for uncommitted work
# `cm fix` resets its workspace with `git checkout HEAD -- . && git clean -fd` (observed in cm 0.16.0, where only the
# sandbox kept it from succeeding), and stashing would hide the very code that needs fixing. Committing the work first
# keeps it visible to `cm fix` and makes every reset harmless. At exit the loop resets back to the original base, so the
# user's changes come back uncommitted (now including the applied fixes) unless --keep-commits is given.
CLEAN_EXCLUDES=(-e .codemender -e .cm_project -e .exploit -e .cache -e .npm -e .cargo -e .local -e .config)
drop_uncommitted_changes() {
  git checkout -q HEAD -- . 2>/dev/null || true
  git clean -fdq "${CLEAN_EXCLUDES[@]}" 2>/dev/null || true
}

# Stage a fix the way the official CodeMender autofix job does: changes to files already in the repository, plus new
# source files the fix adds (for example a sanitizer helper). Other new files (test output, logs) stay out of the commit.
# CodeMender's own ignore-file edits are dropped as well: cm verify appends ".exploit/" to .gitignore and cm fix can create
# a "# CodeMender enforced ignores" .gitignore in its workspace, while .git/info/exclude already covers those paths.
stage_fix_changes() {
  local path line changes only_exploit
  while IFS= read -r path; do
    [ -n "${path}" ] || continue
    changes="$(git diff -U0 -- "${path}" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' || true)"
    only_exploit=true
    while IFS= read -r line; do
      case "${line}" in
        "+.exploit"|"+.exploit/"|"+") ;;
        *) only_exploit=false ;;
      esac
    done <<< "${changes}"
    if [ -n "${changes}" ] && [ "${only_exploit}" = true ]; then
      git checkout -q -- "${path}"
    fi
  done < <(git diff --name-only -- '.gitignore' '*/.gitignore')
  while IFS= read -r -d '' path; do
    if grep -q '^# CodeMender enforced ignores' "${path}"; then
      rm -f -- "${path}"
    fi
  done < <(git ls-files --others --exclude-standard -z -- '.gitignore' '*/.gitignore')

  git add -u -- . ':!*.sarif'
  while IFS= read -r -d '' path; do
    case "${path}" in
      *.py|*.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.go|*.java|*.kt|*.kts|*.rb|*.php|*.rs|*.c|*.cc|*.cpp|*.cxx|*.h|*.hh|*.hpp|*.hxx|*.cs|*.sol|*.tf|*.hcl)
        git add -- "${path}"
        ;;
      *)
        echo "ℹ️  Leaving new non-source file out of the fix commit: ${path}"
        ;;
    esac
  done < <(git ls-files --others --exclude-standard -z -- . ':!*.sarif')
}

CHECKPOINT_BASE=""
finish() {
  local rc=$?
  trap - EXIT
  if [ -n "${CHECKPOINT_BASE}" ]; then
    # Anything still uncommitted here is a leftover patch from cm fix; the user's work is safe in the checkpoint.
    drop_uncommitted_changes
    if [ "${KEEP_COMMITS}" = true ]; then
      echo "ℹ️  Kept the checkpoint and security fix commits on top of $(git rev-parse --short "${CHECKPOINT_BASE}")."
    else
      git reset -q --mixed "${CHECKPOINT_BASE}"
      echo "🔄 Restored your uncommitted changes (now including any applied security fixes) on top of $(git rev-parse --short "${CHECKPOINT_BASE}"). Previously staged changes are now unstaged."
    fi
  fi
  exit "${rc}"
}
trap finish EXIT
trap 'exit 130' INT TERM

if ! git rev-parse --verify -q HEAD >/dev/null; then
  echo "❌ cm fix needs a repository with at least one commit." >&2
  exit 1
fi

# Let the wrapper register CodeMender's runtime paths in .git/info/exclude before anything is staged.
"${CM_EXEC}" --version >/dev/null 2>&1 || true

DIRTY_FILES="$(git status --porcelain 2>/dev/null | grep -vE '^.. (\.codemender/|\.cm_project$|\.exploit/|\.cache/|\.npm/|\.cargo/|\.local/|\.config/|.*\.sarif$)' || true)"
if [ -n "${DIRTY_FILES}" ]; then
  BASE_SHA="$(git rev-parse HEAD)"
  git add -A -- . ':!*.sarif'
  if git commit -q --no-verify -m "wip(cm): checkpoint before security remediation"; then
    CHECKPOINT_BASE="${BASE_SHA}"
    echo "📌 Checkpointed uncommitted work as $(git rev-parse --short HEAD) so cm fix can see it and its workspace reset cannot delete it."
  else
    git reset -q
    echo "❌ Could not create the checkpoint commit (check git user.name / user.email). Nothing was changed." >&2
    exit 1
  fi
fi

# 3. Choose remediation targets
#   explicit IDs -> fix exactly those findings
#   --all-open   -> OPEN / REOPENED findings from the local state database (for example from an earlier full scan).
#                   Diff scans never update stored statuses, so this list can include findings that are already fixed.
#   default      -> findings introduced by the current change, from a diff scan of everything since the base: the
#                   checkpoint base when uncommitted work was checkpointed, else --base, else the upstream branch.
#                   The change is re-scanned after every fix to confirm it and to pick the next target.
DIFF_SCAN="${SCRIPT_DIR}/cm_diff_scan.sh"
STATE_DIR="${PROJECT_ROOT}/.codemender"
SCAN_REPORT="${STATE_DIR}/remediate-scan.json"
PREV_REPORT="${STATE_DIR}/remediate-scan.prev.json"
ATTEMPTED=()
FIXED=()
FAILED=()

if [ ${#TARGET_FIDS[@]} -gt 0 ]; then
  MODE="explicit"
elif [ "${ALL_OPEN}" = true ]; then
  MODE="all-open"
else
  MODE="diff"
fi
LOOP_BASE="${CHECKPOINT_BASE:-${BASE_REF}}"

have_python() { command -v python3 >/dev/null 2>&1; }

# Diff scan of the whole change since LOOP_BASE (report only: the loop decides what blocks).
scan_change() {
  local args=(--scope branch --fail-on "" --output "${SCAN_REPORT}")
  if [ -n "${LOOP_BASE}" ]; then
    args+=(--base "${LOOP_BASE}")
  fi
  bash "${DIFF_SCAN}" "${args[@]}"
}

# Next non-legacy finding in the latest diff report that has not been attempted yet (most severe first).
next_diff_target() {
  [ -s "${SCAN_REPORT}" ] || return 0
  if have_python; then
    python3 - "${SCAN_REPORT}" "${ATTEMPTED[@]+"${ATTEMPTED[@]}"}" <<'PY'
import json, sys

report, attempted = sys.argv[1], set(sys.argv[2:])
try:
    findings = json.load(open(report))
except Exception:
    sys.exit(0)
rank = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}
candidates = [
    f for f in findings
    if f.get("finding_id") and f["finding_id"] not in attempted
    and not str(f.get("title", "")).startswith("[LEGACY / UNTOUCHED]")
]
candidates.sort(key=lambda f: rank.get(str(f.get("severity", "")).upper(), 9))
if candidates:
    print(candidates[0]["finding_id"])
PY
  elif command -v jq >/dev/null 2>&1; then
    local fid
    while IFS= read -r fid; do
      case " ${ATTEMPTED[*]-} " in
        *" ${fid} "*) continue ;;
      esac
      echo "${fid}"
      return 0
    done < <(jq -r '.[] | select((.title // "") | startswith("[LEGACY / UNTOUCHED]") | not) | .finding_id // empty' "${SCAN_REPORT}" 2>/dev/null)
  else
    echo "⚠️  Diff-driven remediation needs python3 or jq to read ${SCAN_REPORT}." >&2
  fi
  return 0
}

# Explains why a fix looks incomplete (target still reported, or new findings appeared); exit 0 when it does.
fix_regressed() {
  have_python || return 1
  python3 - "${PREV_REPORT}" "${SCAN_REPORT}" "$1" <<'PY'
import json, sys

def load(path):
    try:
        return [f for f in json.load(open(path)) if not str(f.get("title", "")).startswith("[LEGACY / UNTOUCHED]")]
    except Exception:
        return []

before, after, target = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
key = lambda f: f.get("fingerprint") or f.get("finding_id")
target_keys = {key(f) for f in before if f.get("finding_id") == target} or {target}
before_keys = {key(f) for f in before}
still = [f for f in after if f.get("finding_id") == target or key(f) in target_keys]
added = [f for f in after if key(f) not in before_keys]
if still:
    print(f"the target is still reported: {still[0].get('title', '')}")
elif added:
    print(f"the fix introduced {len(added)} new finding(s), for example: {added[0].get('title', '')}")
else:
    sys.exit(1)
PY
}

# One fix: cm fix, outer build gate, autofix-style staging, commit. Returns 0 when a fix commit was created.
remediate_one() {
  local fid="$1"
  echo "🛠️  Remediating finding: ${fid}"
  if ! "${CM_EXEC}" fix "${fid}" -c "${GUIDANCE}" --bypass-warning -y; then
    echo "⚠️  cm fix failed for ${fid}; dropping any partial patch."
    drop_uncommitted_changes
    return 1
  fi
  echo "🧪 Running outer-shell build hard gate: ${OUTER_BUILD_CMD}"
  if ! eval "${OUTER_BUILD_CMD}"; then
    echo "❌ Outer build validation failed for ${fid}! Reverting broken patch..."
    drop_uncommitted_changes
    return 1
  fi
  # Runtime/cache paths (.codemender/, .exploit/, .cache/, ...) stay out via .git/info/exclude (registered by cm_exec.sh).
  stage_fix_changes
  if git diff --cached --quiet; then
    echo "ℹ️  No file modifications produced for ${fid}."
    return 1
  fi
  # --no-verify: the loop runs its own build and security gates; user hooks must not block internal commits
  git commit -q --no-verify -m "security(cm): fix ${fid}"
  echo "✅ Committed verified fix for ${fid}"
  return 0
}

revert_last_fix() {
  echo "↩️  Reverting the fix commit for $1 (--strict)."
  git reset -q --hard HEAD~1
}

if [ "${MODE}" = "diff" ]; then
  echo "🔍 Scanning the change since ${LOOP_BASE:-the upstream branch} for findings to remediate..."
  if ! scan_change; then
    echo "❌ Could not scan the change. Pass finding IDs, --all-open, or --base <ref>." >&2
    exit 1
  fi
  while [ ${#ATTEMPTED[@]} -lt "${MAX_FIXES}" ]; do
    fid="$(next_diff_target)"
    [ -n "${fid}" ] || break
    ATTEMPTED+=("${fid}")
    if ! remediate_one "${fid}"; then
      FAILED+=("${fid}")
      continue
    fi
    cp "${SCAN_REPORT}" "${PREV_REPORT}"
    echo "🔍 Re-scanning the change to confirm the fix and pick the next target..."
    if ! scan_change; then
      echo "⚠️  Re-scan failed; stopping after this fix."
      FIXED+=("${fid}")
      break
    fi
    if reason="$(fix_regressed "${fid}")"; then
      echo "⚠️  The fix for ${fid} looks incomplete: ${reason}"
      if [ "${STRICT}" = true ]; then
        revert_last_fix "${fid}"
        cp "${PREV_REPORT}" "${SCAN_REPORT}"
        FAILED+=("${fid}")
        continue
      fi
    fi
    FIXED+=("${fid}")
  done
else
  if [ "${MODE}" = "all-open" ]; then
    # Supports jq, python3, or pure awk fallback; findings labeled [LEGACY / UNTOUCHED] are skipped (jq / python3).
    REPORT_JSON="$("${CM_EXEC}" report -f json 2>/dev/null || true)"
    if command -v jq >/dev/null 2>&1; then
      FINDINGS_RAW="$(printf '%s' "${REPORT_JSON}" | sed -n '/^\[/,$p' | jq -r '.[] | select(.status != "FIXED" and .status != "DISMISSED") | select((.title // "") | startswith("[LEGACY / UNTOUCHED]") | not) | (.finding_id // .id // empty)' 2>/dev/null || true)"
    elif have_python; then
      FINDINGS_RAW="$(printf '%s' "${REPORT_JSON}" | python3 -c '
import sys, json
try:
    raw = sys.stdin.read()
    candidates = [i for i in (raw.find("["), raw.find("{")) if i != -1]
    start = min(candidates) if candidates else -1
    data = json.loads(raw[start:]) if start != -1 else []
    items = data if isinstance(data, list) else data.get("findings", [])
    for f in (items if isinstance(items, list) else []):
        if isinstance(f, dict) and f.get("status") not in ("FIXED", "DISMISSED") and not str(f.get("title", "")).startswith("[LEGACY / UNTOUCHED]"):
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
      [ -z "${fid}" ] && continue
      TARGET_FIDS+=("${fid}")
    done <<< "${FINDINGS_RAW}"
  fi

  if [ ${#TARGET_FIDS[@]} -eq 0 ]; then
    echo "✅ No actionable (OPEN / REOPENED) findings to remediate."
    exit 0
  fi

  for fid in "${TARGET_FIDS[@]}"; do
    [ -n "${fid}" ] || continue
    if ! remediate_one "${fid}"; then
      FAILED+=("${fid}")
      continue
    fi
    # Regression gate: the fix commit itself must not introduce blocking findings.
    echo "🔍 Scanning the fix commit for regressions..."
    gate_rc=0
    bash "${DIFF_SCAN}" --scope last-commit --fail-on "${FAIL_ON}" --output "${STATE_DIR}/remediate-last-commit.json" || gate_rc=$?
    case "${gate_rc}" in
      0)
        FIXED+=("${fid}")
        ;;
      1)
        echo "⚠️  The fix for ${fid} introduced blocking findings (--fail-on=${FAIL_ON})."
        if [ "${STRICT}" = true ]; then
          revert_last_fix "${fid}"
          FAILED+=("${fid}")
        else
          FIXED+=("${fid}")
        fi
        ;;
      *)
        echo "⚠️  Could not scan the fix commit for ${fid}; keeping it."
        FIXED+=("${fid}")
        ;;
    esac
  done
fi

echo "📋 Remediation summary: ${#FIXED[@]} fixed${FIXED[0]+ (${FIXED[*]})}, ${#FAILED[@]} not fixed${FAILED[0]+ (${FAILED[*]})}."
if [ "${MODE}" = "diff" ] && [ -s "${SCAN_REPORT}" ]; then
  echo "   Latest diff report of the change: ${SCAN_REPORT}"
fi
