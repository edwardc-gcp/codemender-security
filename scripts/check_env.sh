#!/usr/bin/env bash
# ==============================================================================
# CodeMender Security Plugin - Environment & Readiness Diagnostic Utility
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Locate the plugin root: this script ships both in scripts/ and in skills/<skill>/scripts/.
PLUGIN_ROOT="${SCRIPT_DIR}"
while [ "${PLUGIN_ROOT}" != "/" ] && [ ! -f "${PLUGIN_ROOT}/plugin.json" ] && [ ! -f "${PLUGIN_ROOT}/.claude-plugin/plugin.json" ]; do
  PLUGIN_ROOT="$(dirname "${PLUGIN_ROOT}")"
done
if [ "${PLUGIN_ROOT}" = "/" ]; then
  PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
PLUGIN_VERSION="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${PLUGIN_ROOT}/plugin.json" 2>/dev/null | head -n 1 || true)"

# The skills rely on diff scans (`cm find --diff --staged`) and the 0.16.0 status model.
MIN_CM_VERSION="0.16.0"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ACTIONS=()

# version_ge A B: true when version A >= version B (numeric x.y.z).
version_ge() {
  local IFS=.
  local -a a b
  read -r -a a <<< "$1"
  read -r -a b <<< "$2"
  local i x y
  for i in 0 1 2; do
    x="${a[i]:-0}"
    y="${b[i]:-0}"
    if ((10#${x} > 10#${y})); then return 0; fi
    if ((10#${x} < 10#${y})); then return 1; fi
  done
  return 0
}

echo "========================================================================"
echo " 🛡️  CodeMender Security Plugin (v${PLUGIN_VERSION:-unknown}) - Diagnostic Health Check"
echo "========================================================================"

# 1. Check CodeMender Binary (the wrappers run `cm` from PATH)
CM_BIN=""
CM_ON_PATH=false
CM_STATUS="❌ Missing"
CM_VER="N/A"
CM_VERSION_OK=false
if command -v cm >/dev/null 2>&1; then
  CM_BIN="$(command -v cm)"
  CM_ON_PATH=true
  CM_STATUS="✔ Installed (${CM_BIN})"
else
  for candidate in "${HOME}/.local/bin/cm" "${HOME}/bin/cm" "/usr/local/bin/cm"; do
    if [ -x "${candidate}" ]; then
      CM_BIN="${candidate}"
      CM_STATUS="⚠️ Installed at ${candidate}, but not on PATH"
      ACTIONS+=("Add $(dirname "${candidate}") to PATH: the plugin scripts run 'cm' from PATH.")
      break
    fi
  done
fi

if [ -n "${CM_BIN}" ]; then
  CM_VER="$("${CM_BIN}" --version 2>/dev/null | head -n 1 || true)"
  CURR_SEMVER="$(printf '%s' "${CM_VER}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
  CM_VER="${CM_VER:-unknown}"
  if [ -n "${CURR_SEMVER}" ] && version_ge "${CURR_SEMVER}" "${MIN_CM_VERSION}"; then
    CM_VERSION_OK=true
  fi

  # Non-blocking check against official stable manifest (1.5s timeout)
  MANIFEST_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3Astable%3Astable.json:download?alt=media"
  REMOTE_VER="$(curl -m 1.5 -fsSL "${MANIFEST_URL}" 2>/dev/null | grep -o '"version": "[^"]*"' | cut -d'"' -f4 | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)"
  if [ -n "${REMOTE_VER}" ] && [ -n "${CURR_SEMVER}" ]; then
    if version_ge "${CURR_SEMVER}" "${REMOTE_VER}"; then
      CM_VER="${CM_VER} (Latest)"
    else
      CM_VER="${CM_VER} ⚠️ (Update available: ${REMOTE_VER})"
    fi
  fi

  if [ "${CM_VERSION_OK}" != true ]; then
    CM_VER="${CM_VER} ❌ (${MIN_CM_VERSION} or later required)"
    ACTIONS+=("Update CodeMender to ${MIN_CM_VERSION} or later (ask before running install_cm.sh or 'cm update').")
  fi
else
  ACTIONS+=("Install the CodeMender CLI (ask before running install_cm.sh).")
fi

# 2. Check credentials, project, endpoint, and authorization.
# Resolve the project the way cm_exec.sh does, then let `cm health` (no repository access, no writes, no billing) test
# every layer: credentials (10), config (20), reachability (30), authorization (40), timeout (50).
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-}"
if [ -z "${GCP_PROJECT}" ] && command -v gcloud >/dev/null 2>&1; then
  GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
fi
HEALTH_LABEL="CodeMender Health"
HEALTH_STATUS="❌ Not checked (cm missing)"
HEALTH_OK=false

if [ -n "${CM_BIN}" ]; then
  HEALTH_ENV=()
  if [ -n "${GCP_PROJECT}" ]; then
    HEALTH_ENV+=("GOOGLE_CLOUD_PROJECT=${GCP_PROJECT}")
  fi
  if [ -d "${PROJECT_ROOT}/.codemender" ]; then
    HEALTH_ENV+=("CM_HOME=${PROJECT_ROOT}/.codemender")
  fi
  HEALTH_RC=0
  HEALTH_JSON="$(env ${HEALTH_ENV[@]+"${HEALTH_ENV[@]}"} "${CM_BIN}" health --json --timeout 20s 2>/dev/null)" || HEALTH_RC=$?

  HEALTH_PROJECT=""
  if command -v python3 >/dev/null 2>&1; then
    HEALTH_SUMMARY="$(python3 - "${HEALTH_JSON}" <<'PY' 2>/dev/null || true
import json, sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
layers = data.get("layers") or []
print(data.get("project_id") or "")
if data.get("status") == "healthy":
    others = [l.get("layer", "?") for l in layers if l.get("status") not in ("passed", "failed")]
    summary = "✔ Healthy (" + ", ".join(l.get("layer", "?") for l in layers) + ")"
    if others:
        summary += " ⚠️ not fully verified: " + ", ".join(others)
    print(summary)
else:
    failed = next((l for l in layers if l.get("status") == "failed"), {})
    lines = (failed.get("error") or failed.get("detail") or data.get("error") or "").strip().splitlines()
    reason = (": " + lines[0][:160]) if lines else ""
    print("❌ %s check failed (exit %s)%s" % (failed.get("layer", "health"), data.get("exit_code", "?"), reason))
PY
)"
    HEALTH_PROJECT="$(printf '%s\n' "${HEALTH_SUMMARY}" | sed -n '1p')"
    HEALTH_STATUS="$(printf '%s\n' "${HEALTH_SUMMARY}" | sed -n '2p')"
  fi
  if [ -z "${HEALTH_STATUS}" ] || [ "${HEALTH_STATUS}" = "❌ Not checked (cm missing)" ]; then
    if [ "${HEALTH_RC}" -eq 0 ] && printf '%s' "${HEALTH_JSON}" | grep -q '"status": *"healthy"'; then
      HEALTH_STATUS="✔ Healthy"
    else
      HEALTH_STATUS="❌ cm health failed (exit ${HEALTH_RC})"
    fi
  fi
  [ -n "${HEALTH_PROJECT}" ] && GCP_PROJECT="${HEALTH_PROJECT}"

  case "${HEALTH_RC}" in
    0) HEALTH_OK=true ;;
    10) ACTIONS+=("Credentials: run 'gcloud auth application-default login' and set GOOGLE_CLOUD_PROJECT (or 'gcloud config set project <id>').") ;;
    20) ACTIONS+=("Config: fix .codemender/config.yaml (team_id, backend, kms_key).") ;;
    30) ACTIONS+=("Reachability: check network access to the CodeMender endpoint (proxy, DNS, VPC Service Controls).") ;;
    40) ACTIONS+=("Authorization: get the Agent Platform User role (roles/aiplatform.user) on a project with CodeMender access.") ;;
    50) ACTIONS+=("Timeout: the health check timed out; check the network and retry.") ;;
    *) ACTIONS+=("Run 'cm health --json' for details (exit ${HEALTH_RC}).") ;;
  esac
elif command -v gcloud >/dev/null 2>&1; then
  # Without cm, at least check Application Default Credentials (what cm uses), not the gcloud user login.
  HEALTH_LABEL="Google Cloud ADC"
  if gcloud auth application-default print-access-token >/dev/null 2>&1; then
    HEALTH_STATUS="✔ Valid (run this check again after installing cm)"
  else
    HEALTH_STATUS="⚠️ Needs 'gcloud auth application-default login'"
    ACTIONS+=("Run 'gcloud auth application-default login'.")
  fi
fi

# 3. Check Workspace & Git Isolation (worktree-aware, like cm_exec.sh)
GIT_EXCLUDE_STATUS="⚠️ Not Configured (cm_exec.sh adds the entries on first use)"
EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && grep -q "\.codemender" "${EXCLUDE_FILE}" 2>/dev/null; then
  GIT_EXCLUDE_STATUS="✔ Protected (.git/info/exclude)"
fi

# 4. Check Plugin Components
SKILLS_COUNT="$(find "${PLUGIN_ROOT}/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')"
HOOKS_STATUS="✔ Registered (PreToolUse)"
if [ ! -f "${PLUGIN_ROOT}/scripts/pre_tool_guard.sh" ]; then
  HOOKS_STATUS="❌ Missing Guardrail Hook"
fi

# Print Diagnostic Summary Table
printf "\n%-30s : %s\n" "CodeMender CLI" "${CM_STATUS}"
printf "%-30s : %s\n" "CLI Version" "${CM_VER}"
printf "%-30s : %s\n" "Google Cloud Project" "${GCP_PROJECT:-None}"
printf "%-30s : %s\n" "${HEALTH_LABEL}" "${HEALTH_STATUS}"
printf "%-30s : %s\n" "Active Skills Count" "${SKILLS_COUNT} skills loaded (codemender-audit, codemender-remediate)"
printf "%-30s : %s\n" "Runtime Hook Guard" "${HOOKS_STATUS}"
printf "%-30s : %s\n" "Workspace Data Protection" "${GIT_EXCLUDE_STATUS}"

echo "========================================================================"
if [ "${CM_ON_PATH}" = true ] && [ "${CM_VERSION_OK}" = true ] && [ "${HEALTH_OK}" = true ]; then
  echo "✔ Environment is 100% READY for autonomous CodeMender security tasks."
else
  echo "⚠️ Action required:"
  for action in ${ACTIONS[@]+"${ACTIONS[@]}"}; do
    echo "   - ${action}"
  done
fi
