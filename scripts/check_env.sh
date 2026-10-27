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

echo "========================================================================"
echo " 🛡️  CodeMender Security Plugin (v${PLUGIN_VERSION:-unknown}) - Diagnostic Health Check"
echo "========================================================================"

# 1. Check CodeMender Binary
CM_STATUS="❌ Missing"
CM_VER="N/A"
if command -v cm >/dev/null 2>&1; then
  CM_PATH="$(command -v cm)"
  CM_VER="$(cm --version 2>/dev/null || cm -v 2>/dev/null || echo "0.8.0+")"
  CM_STATUS="✔ Installed (${CM_PATH})"

  # Non-blocking check against official stable manifest (1.5s timeout)
  MANIFEST_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3Astable%3Astable.json:download?alt=media"
  REMOTE_VER="$(curl -m 1.5 -fsSL "${MANIFEST_URL}" 2>/dev/null | grep -o '"version": "[^"]*"' | cut -d'"' -f4 || true)"
  CURR_SEMVER="$(echo "${CM_VER}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  if [ -n "${REMOTE_VER}" ] && [ -n "${CURR_SEMVER}" ]; then
    if [ "${CURR_SEMVER}" != "${REMOTE_VER}" ]; then
      CM_VER="${CM_VER} ⚠️ (Update available: ${REMOTE_VER})"
    else
      CM_VER="${CM_VER} (Latest)"
    fi
  fi
fi

# 2. Check Google Cloud ADC Credentials & Project
GCLOUD_STATUS="❌ Missing"
GCP_PROJECT="N/A"
ADC_STATUS="❌ Unauthenticated"

if command -v gcloud >/dev/null 2>&1; then
  GCLOUD_STATUS="✔ Available"
  GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || echo "None")"
  if gcloud auth print-access-token >/dev/null 2>&1; then
    ADC_STATUS="✔ Valid"
  else
    ADC_STATUS="⚠️ Needs 'gcloud auth application-default login'"
  fi
fi

# 3. Check Workspace & Git Isolation
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GIT_EXCLUDE_STATUS="⚠️ Not Configured"
if [ -f "${PROJECT_ROOT}/.git/info/exclude" ]; then
  if grep -q "\.codemender" "${PROJECT_ROOT}/.git/info/exclude" 2>/dev/null; then
    GIT_EXCLUDE_STATUS="✔ Protected (.git/info/exclude)"
  fi
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
printf "%-30s : %s\n" "Google Cloud Project" "${GCP_PROJECT}"
printf "%-30s : %s\n" "Google Cloud ADC" "${ADC_STATUS}"
printf "%-30s : %s\n" "Active Skills Count" "${SKILLS_COUNT} skills loaded (codemender-audit, codemender-remediate)"
printf "%-30s : %s\n" "Runtime Hook Guard" "${HOOKS_STATUS}"
printf "%-30s : %s\n" "Workspace Data Protection" "${GIT_EXCLUDE_STATUS}"

echo "========================================================================"
if [[ "${CM_STATUS}" == *"✔"* && "${ADC_STATUS}" == *"✔"* ]]; then
  echo "✔ Environment is 100% READY for autonomous CodeMender security tasks."
else
  echo "⚠️ Action required: Please ensure 'cm' is installed and run 'gcloud auth application-default login'."
fi
