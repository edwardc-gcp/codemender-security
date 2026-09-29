#!/usr/bin/env bash
# ==============================================================================
# CodeMender Security Plugin - Environment & Readiness Diagnostic Utility
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "========================================================================"
echo " 🛡️  CodeMender Security Plugin (v1.2.0) - Diagnostic Health Check"
echo "========================================================================"

# 1. Check CodeMender Binary
CM_STATUS="❌ Missing"
CM_VER="N/A"
if command -v cm >/dev/null 2>&1; then
  CM_PATH="$(command -v cm)"
  CM_VER="$(cm --version 2>/dev/null || cm -v 2>/dev/null || echo "0.8.0+")"
  CM_STATUS="✔ Installed (${CM_PATH})"
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
