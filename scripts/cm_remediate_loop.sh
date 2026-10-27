#!/usr/bin/env bash
# Atomic Non-Destructive Multi-Vulnerability Remediation Loop for CodeMender (cm)
# Protects uncommitted work with a checkpoint commit, enforces outer-shell build hard gates,
# prevents committing $HOME cache artifacts, and reconciles AST line numbers after every commit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CM_EXEC="${SCRIPT_DIR}/cm_exec.sh"

GUIDANCE="Apply minimal security fix preserving existing API behavior"
OUTER_BUILD_CMD=""
KEEP_COMMITS=false
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
    -h|--help)
      echo "Usage: $(basename "$0") [-c \"<guidance>\"] [-b \"<outer-build-cmd>\"] [--keep-commits] [finding_id ...]"
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
      drop_uncommitted_changes
      continue
    fi
    # Stage code & newly created helper files. Runtime/cache paths (.codemender/, .exploit/, .cache/, ...) are ignored via
    # .git/info/exclude (registered by cm_exec.sh); naming ignored directories as pathspec exclusions makes newer git
    # abort, so only *.sarif is excluded explicitly.
    git add -A -- . ':!*.sarif'
    if ! git diff --cached --quiet; then
      # --no-verify: the loop runs its own build and security gates; user hooks must not block internal commits
      git commit -q --no-verify -m "security(cm): fix ${fid}"
      echo "✅ Committed verified fix for ${fid}"
      echo "🔍 Reconciling AST line numbers via differential cm find before next finding..."
      if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
        "${CM_EXEC}" find . --diff=HEAD~1 -y || true
      else
        "${CM_EXEC}" find . -y || true
      fi
    else
      echo "ℹ️  No file modifications produced for ${fid}."
    fi
  else
    echo "⚠️  cm fix failed for ${fid}; cleaning working tree and continuing..."
    drop_uncommitted_changes
  fi
done
