#!/usr/bin/env bash
# Scans local changes with CodeMender diff mode (`cm find --diff`): the Secure Inner Loop scanner and git hook entry point.
#
# Usage: cm_diff_scan.sh [--scope auto|working|staged|branch|last-commit] [--base REF] [--path PATH]
#                        [--fail-on SEVERITIES] [--depth N] [--dry-run] [--output FILE] [-c CONTEXT]
#                        [-- CM_FIND_FLAGS...]
#
# Scopes:
#   working      uncommitted changes to tracked files (vs HEAD) plus untracked source files; `cm find --diff` ignores
#                untracked files, so they are registered with `git add -N` for the scan only and restored afterwards
#   staged       only what is staged for the next commit (`--diff --staged`), for pre-commit checks
#   branch       everything since the merge base with --base (default: upstream branch, else origin/HEAD)
#   last-commit  the most recent commit (`--diff=HEAD~1`)
#   auto         (default) working if there are unstaged or untracked source changes, else staged if something is
#                staged, else branch if the branch is ahead of its upstream, else nothing to scan
#
# --depth N      impact depth in hops (`--diff-depth`), for cm 0.17.0 and earlier. cm 0.18.0 removed that flag: its diff
#                scans always resolve 1 hop, so there --depth 1 changes nothing, and a larger value is refused rather
#                than letting a narrower scan look clean.
# --dry-run      cm 0.18.0 and later: preview what the scan would cover (changed files, 1-hop neighbors, and an
#                architecture summary) without a scan session or tokens. The preview goes to
#                .codemender/last-diff-scan.dry-run.json (or --output); the findings report and the .meta file that the
#                git hook reuses stay untouched.
#
# Flags after `--` go to `cm find` unchanged, for example --model gemini-4-argon, --diff-max-neighbors 20,
# --diff-workers 8, --diff-job-timeout 20m, --fail-on-truncation, or --include-hidden. The script sets --diff, --staged,
# --format, --output, --fail-on, and -y itself, and refuses flags that turn off a safety boundary (--sandbox,
# --allow-all-paths, --allow-all-commands, and the older --unrestricted), cm 0.18.0's --dry-run (use the option above:
# the scope preview isn't a findings report), and the interactive --validate.
#
# Exit codes: 0 = no blocking findings, nothing to scan, or a completed --dry-run, 1 = blocking findings (per
#             --fail-on, default CRITICAL,HIGH; an empty value only reports), 2 = tool, usage, or environment error,
#             or an INCOMPLETE scan (a file job failed, so a clean result doesn't cover every changed file). Since cm
#             0.17.0, setup failures have their own cm exit codes (10 credentials, 20 config, 30 reachability,
#             40 authorization, 50 timeout); they also exit 2, with a hint for that layer.
# The JSON report is written to --output (default: .codemender/last-diff-scan.json) with a .meta file next to it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CM_EXEC="${SCRIPT_DIR}/cm_exec.sh"

SCOPE="auto"
BASE=""
TARGET_PATH="."
FAIL_ON="CRITICAL,HIGH"
DEPTH=""
DRY_RUN=false
OUTPUT=""
CONTEXT=""
EXTRA_ARGS=()

# Prints the header comment (from line 2 up to the first line that isn't a comment).
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

# Options that take a value stop with a usage error when it's missing (instead of looping forever on `shift 2`).
need_value() {
  if [ "$2" -lt 2 ]; then
    echo "❌ $1 needs a value." >&2
    usage >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scope) need_value "$1" $#; SCOPE="$2"; shift 2 ;;
    --base) need_value "$1" $#; BASE="$2"; shift 2 ;;
    --path) need_value "$1" $#; TARGET_PATH="$2"; shift 2 ;;
    --fail-on) need_value "$1" $#; FAIL_ON="$2"; shift 2 ;;
    --depth) need_value "$1" $#; DEPTH="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --output) need_value "$1" $#; OUTPUT="$2"; shift 2 ;;
    -c|--context) need_value "$1" $#; CONTEXT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    *) echo "❌ Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -n "${DEPTH}" ]; then
  case "${DEPTH}" in
    *[!0-9]*|0*) echo "❌ --depth needs a whole number of hops (1 or more), not: ${DEPTH}" >&2; exit 2 ;;
  esac
fi

for arg in ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; do
  case "${arg}" in
    --diff|--diff=*|--staged|--quick|--deep|--format|--format=*|--output|--output=*|--fail-on|--fail-on=*|-y|--yes)
      echo "❌ ${arg} is set by cm_diff_scan.sh; use its own options (--scope, --base, --fail-on, --output) instead." >&2
      exit 2
      ;;
    --unrestricted|--unrestricted=*|--sandbox|--sandbox=*|--allow-all-paths|--allow-all-paths=*|--allow-all-commands|--allow-all-commands=*)
      echo "❌ ${arg} changes a CodeMender safety boundary (sandbox, path boundary, or command policy), so cm_diff_scan.sh refuses it. Only the user can approve that, for a cm_exec.sh find run." >&2
      exit 2
      ;;
    --dry-run|--dry-run=*)
      echo "❌ ${arg} makes cm 0.18.0 write a scope preview instead of findings, so cm_diff_scan.sh refuses it after --: a preview must never pass for a clean scan that the git hook could reuse. Use cm_diff_scan.sh --dry-run instead, which keeps the preview apart." >&2
      exit 2
      ;;
    --validate|--validate=*)
      echo "❌ ${arg} asks you questions interactively, and cm_diff_scan.sh runs cm non-interactively, so it refuses it. Run it yourself in a terminal: bash \"${CM_EXEC}\" find . --validate" >&2
      exit 2
      ;;
  esac
done

case "${SCOPE}" in
  auto|working|staged|branch|last-commit) ;;
  *) echo "❌ Unknown scope: ${SCOPE}" >&2; exit 2 ;;
esac

# Resolve the scan target (physical path, to match git's view of the repository) before moving to the repository root.
if [ -d "${TARGET_PATH}" ]; then
  TARGET_ABS="$(cd "${TARGET_PATH}" && pwd -P)"
  TARGET_DIR="${TARGET_ABS}"
elif [ -e "${TARGET_PATH}" ]; then
  TARGET_DIR="$(cd "$(dirname "${TARGET_PATH}")" && pwd -P)"
  TARGET_ABS="${TARGET_DIR}/$(basename "${TARGET_PATH}")"
else
  echo "❌ Path not found: ${TARGET_PATH}" >&2
  exit 2
fi

if ! PROJECT_ROOT="$(git -C "${TARGET_DIR}" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "❌ Not a git repository. Diff mode needs git; for a quick look use: bash \"${CM_EXEC}\" find <path> --quick -y" >&2
  exit 2
fi
cd "${PROJECT_ROOT}" || exit 2
if ! git rev-parse --verify -q HEAD >/dev/null; then
  echo "❌ The repository has no commits yet, so there is nothing to diff against. Use: bash \"${CM_EXEC}\" find . --quick -y" >&2
  exit 2
fi
# Let the wrapper register CodeMender's runtime paths (.codemender/, ...) in .git/info/exclude before writing reports,
# and read the cm version for the flags that changed between releases.
CM_VERSION="$(bash "${CM_EXEC}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"

# version_ge A B: true when version A (MAJOR.MINOR.PATCH) is at least B.
version_ge() {
  [ -n "$1" ] || return 1
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = "$2" ]
}

# cm 0.18.0 removed --diff-depth: its diff scans always resolve 1 hop. A deeper request can't be honored, and a narrower
# scan must not look like the clean result that was asked for, so stop instead.
if [ -n "${DEPTH}" ] && version_ge "${CM_VERSION}" 0.18.0; then
  if [ "${DEPTH}" = "1" ]; then
    echo "ℹ️  cm ${CM_VERSION} always resolves 1-hop impact, so --depth 1 is already its behavior (not passed to cm)."
    DEPTH=""
  else
    echo "❌ --depth ${DEPTH} needs cm 0.17.0 or earlier: cm ${CM_VERSION} removed --diff-depth, and its diff scans resolve only 1-hop callers. To cover more of the change's impact, pass -- --diff-max-neighbors 20 --fail-on-truncation; for callers farther away, ask the user before a deep scan of their directories: bash \"${CM_EXEC}\" find <dir> -y" >&2
    exit 2
  fi
fi
if [ "${DRY_RUN}" = true ] && ! version_ge "${CM_VERSION}" 0.18.0; then
  echo "❌ --dry-run needs cm 0.18.0 or later (installed: ${CM_VERSION:-unknown})." >&2
  exit 2
fi

STATE_DIR="${PROJECT_ROOT}/.codemender"
ITA_RECORD="${STATE_DIR}/.diff_scan_intent_to_add"
# A dry run writes its scope preview (and log) apart from the findings report, so it can't replace a scan result.
if [ "${DRY_RUN}" = true ]; then
  REPORT="${OUTPUT:-${STATE_DIR}/last-diff-scan.dry-run.json}"
  SCAN_LOG="${STATE_DIR}/last-diff-scan.dry-run.log"
else
  REPORT="${OUTPUT:-${STATE_DIR}/last-diff-scan.json}"
  SCAN_LOG="${STATE_DIR}/last-diff-scan.log"
fi

# Restore untracked files that an earlier (or this) run registered with `git add -N`, unless the user has since staged them.
undo_intent_to_add() {
  [ -f "${ITA_RECORD}" ] || return 0
  local path
  while IFS= read -r -d '' path; do
    if git diff --cached --quiet -- "${path}" 2>/dev/null && ! git cat-file -e "HEAD:${path}" 2>/dev/null; then
      git reset -q -- "${path}" 2>/dev/null || true
    fi
  done < "${ITA_RECORD}"
  rm -f "${ITA_RECORD}"
}
undo_intent_to_add

# Source extensions that make a change worth scanning: scan.extensions.include from config.yaml, else cm 0.16 defaults.
EXT_LIST=""
if [ -f "${STATE_DIR}/config.yaml" ]; then
  EXT_LIST="$(sed -nE 's/^[[:space:]]+include:[[:space:]]*\[(.*)\].*/\1/p' "${STATE_DIR}/config.yaml" | head -n 1 \
    | tr -d ' "' | tr ',' '\n' | sed -nE 's/^\.([A-Za-z0-9_+-]+)$/\1/p' | paste -s -d '|' -)"
fi
[ -n "${EXT_LIST}" ] || EXT_LIST="py|java|go|js|jsx|mjs|cjs|ts|tsx|c|cc|cpp|cxx|h|hh|hpp|hxx|inl|ipp|cs|rs|kt|kts|rb|php|sol|tf|hcl"
EXT_RE="\\.(${EXT_LIST})$"

is_source() { [[ "$1" =~ ${EXT_RE} ]]; }

has_untracked_source() {
  local path
  while IFS= read -r -d '' path; do
    is_source "${path}" && return 0
  done < <(git ls-files --others --exclude-standard -z -- "${TARGET_ABS}")
  return 1
}

default_branch_base() {
  local ref candidate
  if ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
    echo "${ref}"
    return 0
  fi
  if ref="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    echo "${ref}"
    return 0
  fi
  for candidate in origin/main origin/master main master; do
    if git rev-parse --verify -q "${candidate}" >/dev/null; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

if [ "${SCOPE}" = "auto" ]; then
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if ! git diff --quiet -- "${TARGET_ABS}" || has_untracked_source; then
    SCOPE="working"
  elif ! git diff --cached --quiet -- "${TARGET_ABS}"; then
    SCOPE="staged"
  elif [ -n "${upstream}" ] && [ "$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)" -gt 0 ]; then
    SCOPE="branch"
  else
    mkdir -p "$(dirname "${REPORT}")"
    printf '[]\n' > "${REPORT}"
    echo "✅ Nothing to scan: no uncommitted, staged, or unpushed changes."
    exit 0
  fi
  echo "ℹ️  Auto-selected the ${SCOPE} scope."
fi

DIFF_REF=""
case "${SCOPE}" in
  branch)
    if [ -z "${BASE}" ] && ! BASE="$(default_branch_base)"; then
      echo "❌ No base branch found. Pass --base <ref> (for example --base origin/main) after fetching it." >&2
      exit 2
    fi
    if ! git rev-parse --verify -q "${BASE}^{commit}" >/dev/null; then
      echo "❌ Base ref not found: ${BASE}. Fetch it first (for example: git fetch origin)." >&2
      exit 2
    fi
    DIFF_REF="$(git merge-base HEAD "${BASE}" 2>/dev/null || echo "${BASE}")"
    echo "ℹ️  Comparing against ${BASE} (merge base $(git rev-parse --short "${DIFF_REF}"))."
    ;;
  last-commit)
    if ! git rev-parse --verify -q HEAD~1 >/dev/null; then
      echo "❌ The repository has a single commit; use --scope working or a full scan instead." >&2
      exit 2
    fi
    DIFF_REF="HEAD~1"
    ;;
esac

changed_files() {
  case "${SCOPE}" in
    working)
      git diff --name-only HEAD -- "${TARGET_ABS}"
      git ls-files --others --exclude-standard -- "${TARGET_ABS}"
      ;;
    staged) git diff --cached --name-only -- "${TARGET_ABS}" ;;
    *) git diff --name-only "${DIFF_REF}" -- "${TARGET_ABS}" ;;
  esac
}

# The .meta file lets callers (such as the git hook) reuse a result: for the staged scope it records the staged tree, so
# the same HEAD, tree, path, and --fail-on mean the same scan.
TARGET_REL="$(git -C "${TARGET_DIR}" rev-parse --show-prefix 2>/dev/null || true)"
if [ ! -d "${TARGET_ABS}" ]; then
  TARGET_REL="${TARGET_REL}$(basename "${TARGET_ABS}")"
fi
write_meta() {
  local tree=""
  # A dry run scans nothing, so it never leaves a result for the git hook to reuse.
  if [ "${DRY_RUN}" = true ]; then
    return 0
  fi
  if [ "${SCOPE}" = "staged" ]; then
    tree="$(git write-tree 2>/dev/null || true)"
  fi
  printf 'scope=%s\npath=%s\nbase=%s\nhead=%s\ntree=%s\nfail_on=%s\nexit_code=%s\ncreated_at=%s\n' "${SCOPE}" \
    "${TARGET_REL:-.}" "${DIFF_REF:-HEAD}" "$(git rev-parse HEAD)" "${tree}" "${FAIL_ON}" "$1" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${REPORT%.json}.meta"
}

# Fast path: skip the scan (and its token cost) when no source file changed. Deletions count: they can remove controls.
RELEVANT=false
while IFS= read -r path; do
  if [ -n "${path}" ] && is_source "${path}"; then
    RELEVANT=true
    break
  fi
done < <(changed_files)
mkdir -p "$(dirname "${REPORT}")"
if [ "${RELEVANT}" = false ]; then
  printf '[]\n' > "${REPORT}"
  write_meta 0
  echo "✅ No security-relevant source changes in the ${SCOPE} scope; skipped the scan (no tokens used)."
  exit 0
fi

# Working scope: make untracked source files visible to `git diff` for the duration of the scan.
if [ "${SCOPE}" = "working" ]; then
  ITA_PATHS=()
  while IFS= read -r -d '' path; do
    if is_source "${path}"; then
      ITA_PATHS+=("${path}")
    fi
  done < <(git ls-files --others --exclude-standard -z -- "${TARGET_ABS}")
  if [ ${#ITA_PATHS[@]} -gt 0 ]; then
    mkdir -p "${STATE_DIR}"
    printf '%s\0' "${ITA_PATHS[@]}" > "${ITA_RECORD}"
    trap undo_intent_to_add EXIT
    trap 'exit 130' INT TERM
    git add -N -- "${ITA_PATHS[@]}"
    echo "ℹ️  Including ${#ITA_PATHS[@]} untracked source file(s) in the scan (git add -N, restored afterwards)."
  fi
fi

CM_ARGS=(find "${TARGET_ABS}")
case "${SCOPE}" in
  working) CM_ARGS+=(--diff) ;;
  staged) CM_ARGS+=(--diff --staged) ;;
  *) CM_ARGS+=("--diff=${DIFF_REF}") ;;
esac
CM_ARGS+=("--fail-on=${FAIL_ON}" --format json --output "${REPORT}" -y)
if [ -n "${DEPTH}" ]; then
  CM_ARGS+=(--diff-depth "${DEPTH}")
fi
if [ -n "${CONTEXT}" ]; then
  CM_ARGS+=(-c "${CONTEXT}")
fi
if [ "${DRY_RUN}" = true ]; then
  CM_ARGS+=(--dry-run)
fi
CM_ARGS+=(${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"})

rm -f "${REPORT}"
mkdir -p "${STATE_DIR}"
bash "${CM_EXEC}" "${CM_ARGS[@]}" 2>&1 | tee "${SCAN_LOG}"
RC=${PIPESTATUS[0]}

if [ "${DRY_RUN}" = true ] && [ "${RC}" -eq 0 ]; then
  echo "ℹ️  Dry run only: nothing was scanned and no tokens were used, so this isn't a security result. Preview: ${REPORT} (the findings report and its .meta file were left untouched)."
  exit 0
fi

# cm 0.16 marks multi-file scans INCOMPLETE when a file job fails ("N succeeded, M failed"); a clean result then
# doesn't cover every changed file.
FAILED_JOBS="$(sed -nE 's/.*\(([0-9]+) succeeded, ([0-9]+) failed\).*/\2/p' "${SCAN_LOG}" 2>/dev/null | tail -n 1)"
INCOMPLETE=false
if [ -n "${FAILED_JOBS}" ] && [ "${FAILED_JOBS}" -gt 0 ]; then
  INCOMPLETE=true
fi

summarize() {
  [ -s "${REPORT}" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${REPORT}" "${PROJECT_ROOT}" <<'PY'
import json, os, sys

report, root = sys.argv[1], sys.argv[2]
try:
    findings = json.load(open(report))
except Exception as exc:
    print(f"⚠️  Could not parse {report}: {exc}")
    sys.exit(0)
if isinstance(findings, dict):
    findings = findings.get("findings", [])
if not findings:
    print("No findings reported for this change.")
    sys.exit(0)

def is_legacy(finding):
    return str(finding.get("title", "")).startswith("[LEGACY / UNTOUCHED]")

def describe(finding):
    path = finding.get("file_path") or ""
    if os.path.isabs(path) and path.startswith(root):
        path = os.path.relpath(path, root)
    location = f"{path}:{finding.get('start_line', '?')}"
    return f"  {finding.get('severity', '?'):<8} {str(finding.get('finding_id', ''))[:8]:<8}  {location:<40}  {finding.get('title', '')}"

introduced = [f for f in findings if not is_legacy(f)]
legacy = [f for f in findings if is_legacy(f)]
print(f"Findings introduced or affected by this change: {len(introduced)}")
for finding in introduced:
    print(describe(finding))
if legacy:
    print(f"Pre-existing findings in untouched code (never block): {len(legacy)}")
    for finding in legacy:
        print(describe(finding))
PY
  elif command -v jq >/dev/null 2>&1; then
    jq -r '.[] | "  \(.severity)  \(.finding_id[0:8])  \(.file_path):\(.start_line)  \(.title)"' "${REPORT}" 2>/dev/null || true
  else
    cat "${REPORT}"
  fi
}

# A findings report is a JSON array (an object with a "findings" array also counts). Anything else, such as the scope
# preview that cm 0.18.0 writes for --dry-run, or a file that doesn't parse, means that nothing was verified.
report_is_findings() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" 2>/dev/null <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(data, list) or (isinstance(data, dict) and isinstance(data.get("findings"), list)) else 1)
PY
  elif command -v jq >/dev/null 2>&1; then
    jq -e 'type == "array" or (type == "object" and (.findings | type) == "array")' "$1" >/dev/null 2>&1
  else
    return 0
  fi
}

if [ "${RC}" -eq 0 ] && [ "${INCOMPLETE}" = true ]; then
  summarize
  echo "❌ INCOMPLETE scan: ${FAILED_JOBS} file job(s) failed (the ❌ lines above), so a clean result doesn't cover every changed file. Re-run the scan; if a large file keeps timing out, pass -- --diff-job-timeout 20m, or check: bash \"${CM_EXEC}\" health --strict" >&2
  exit 2
fi

if [ "${RC}" -eq 0 ] || { [ "${RC}" -eq 1 ] && [ -s "${REPORT}" ]; }; then
  # Only a findings report may count as a result (and be recorded in the .meta file that the git hook reuses).
  if [ -s "${REPORT}" ] && ! report_is_findings "${REPORT}"; then
    echo "❌ cm find exited ${RC}, but ${REPORT} isn't a findings report (a JSON array), so nothing was verified and no .meta was written. Check the flags after --." >&2
    exit 2
  fi
  if [ ! -s "${REPORT}" ]; then
    echo "✅ cm reported no blocking findings in the ${SCOPE} scope (--fail-on=${FAIL_ON:-<report only>}), but it wrote no report, so the git hook won't reuse this result."
    exit 0
  fi
  summarize
  write_meta "${RC}"
  if [ "${RC}" -eq 0 ]; then
    echo "✅ No blocking findings in the ${SCOPE} scope (--fail-on=${FAIL_ON:-<report only>}). Report: ${REPORT}"
  else
    echo "🚨 Blocking findings in the ${SCOPE} scope (--fail-on=${FAIL_ON}). Report: ${REPORT}"
    if [ "${INCOMPLETE}" = true ]; then
      echo "⚠️  The scan is also INCOMPLETE: ${FAILED_JOBS} file job(s) failed, so re-scan after fixing these findings." >&2
    fi
  fi
  exit "${RC}"
fi

# cm 0.17.0+ exits with the failing setup layer's code (the same codes as `cm health`). Other failures, such as a flag
# that this cm release doesn't know, exit 1 without a report: show cm's own error line for those.
CM_ERROR="$(sed -n 's/^Error: //p' "${SCAN_LOG}" 2>/dev/null | head -n 1)"
DETAILS="bash \"${CM_EXEC}\" health --strict"
case "${RC}" in
  10) HINT="credentials: run 'gcloud auth application-default login' and set GOOGLE_CLOUD_PROJECT" ;;
  20) HINT="configuration: fix .codemender/config.yaml, then run cm_config_check.sh and cm_exec.sh init --verify" ;;
  30) HINT="reachability: check network access to the CodeMender endpoint (proxy, DNS, VPC Service Controls)" ;;
  40) HINT="authorization: the caller needs the Agent Platform User role (roles/aiplatform.user) on a project with CodeMender access" ;;
  50) HINT="timeout: check the network and retry" ;;
  *)
    if [ -n "${CM_ERROR}" ]; then
      HINT="cm said: ${CM_ERROR}"
    else
      HINT="check credentials and connectivity"
    fi
    case "${CM_ERROR}" in
      *"unknown flag: --diff-depth"*)
        HINT="${HINT}; cm 0.18.0 removed --diff-depth (diff scans always resolve 1 hop), so drop it" ;;
    esac
    case "${CM_ERROR}" in
      *"unknown flag"*|*"unknown shorthand flag"*|*"flags in the group"*|*"invalid argument"*)
        DETAILS="bash \"${CM_EXEC}\" find --help" ;;
    esac
    ;;
esac
echo "❌ cm find --diff failed (exit ${RC}) without producing a report (${HINT}). Details: ${DETAILS}" >&2
exit 2
