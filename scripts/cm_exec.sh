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
GCP_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"

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

# 3. Auto-inject flags for stateful and rolling display subcommands
EXTRA_ARGS=()
if [ "${1:-}" = "verify" ] || [ "${1:-}" = "fix" ]; then
  HAS_BYPASS=false
  for arg in "$@"; do
    if [ "$arg" = "--bypass-warning" ]; then
      HAS_BYPASS=true
      break
    fi
  done
  if [ "$HAS_BYPASS" = false ]; then
    EXTRA_ARGS+=("--bypass-warning")
  fi
fi

if [ "${1:-}" = "find" ] || [ "${1:-}" = "verify" ] || [ "${1:-}" = "fix" ]; then
  HAS_COMPACT_OR_VERBOSE=false
  for arg in "$@"; do
    if [ "$arg" = "--compact" ] || [ "$arg" = "-v" ] || [ "$arg" = "--verbose" ]; then
      HAS_COMPACT_OR_VERBOSE=true
      break
    fi
  done
  if [ "$HAS_COMPACT_OR_VERBOSE" = false ]; then
    EXTRA_ARGS+=("--compact")
  fi
fi

# 4. Construct execution environment with isolated HOME and forwarded credentials
CM_ENV=(
  "HOME=${PROJECT_ROOT}"
  "CM_REAL_HOME=${REAL_HOME}"
  "GIT_CONFIG_GLOBAL=${REAL_HOME}/.gitconfig"
  "GOOGLE_CLOUD_PROJECT=${GCP_PROJECT}"
)
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then
  CM_ENV+=("GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}")
elif [ -f "${ADC_PATH}" ]; then
  CM_ENV+=("GOOGLE_APPLICATION_CREDENTIALS=${ADC_PATH}")
fi
if [ -d "${REAL_HOME}/.config/gcloud" ]; then
  CM_ENV+=("CLOUDSDK_CONFIG=${REAL_HOME}/.config/gcloud")
fi

exec env "${CM_ENV[@]}" cm "$@" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
