#!/usr/bin/env bash
# Stateless On-the-Fly Workspace Wrapper for Google Cloud CodeMender (cm) CLI
# Prevents $HOME pollution, forwards git/gcloud credentials, and protects .git/info/exclude.

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: $(basename "$0") <cm-subcommand> [args...]" >&2
  exit 1
fi

REAL_HOME="${CM_REAL_HOME:-${HOME}}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ADC_PATH="${REAL_HOME}/.config/gcloud/application_default_credentials.json"
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" gcloud config get-value project 2>/dev/null || true)}"

# 1. Protect runtime and toolchain artifacts in .git/info/exclude from git clean -fd & git add -A
EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "${EXCLUDE_FILE}" ] && [ -d "$(dirname "${EXCLUDE_FILE}")" ]; then
  for entry in \
    ".codemender/" \
    ".cm_project" \
    ".exploit/" \
    ".cache/" \
    ".npm/" \
    ".cargo/" \
    ".local/" \
    ".config/" \
    "codemender-results.sarif" \
    "remediated-results.sarif"; do
    grep -qxF "$entry" "${EXCLUDE_FILE}" 2>/dev/null || echo "$entry" >> "${EXCLUDE_FILE}"
  done
fi

# 2. Zero Data-Loss Guard for `cm init`
if [ "${1:-}" = "init" ]; then
  for arg in "$@"; do
    if [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
      echo "❌ Security Block: Never pass -y/--yes to 'cm init' (prevents overwriting custom .codemender/config.yaml)." >&2
      exit 1
    fi
  done
  if [ -f "${PROJECT_ROOT}/.codemender/config.yaml" ]; then
    echo "ℹ️  ${PROJECT_ROOT}/.codemender/config.yaml already exists; skipping 'cm init'."
    exit 0
  fi
fi

# 3. Execute `cm` with isolated HOME and forwarded host credentials
exec env \
  HOME="${PROJECT_ROOT}" \
  CM_REAL_HOME="${REAL_HOME}" \
  GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" \
  CLOUDSDK_CONFIG="${REAL_HOME}/.config/gcloud" \
  GOOGLE_APPLICATION_CREDENTIALS="${ADC_PATH}" \
  GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}" \
  cm "$@"
