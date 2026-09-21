#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " 🚀 CodeMender CLI (cm) Cross-Platform Installer"
echo "=========================================================="

# 1. Determine target binary directory
TARGET_DIR="${HOME}/bin"
if [ -w "/usr/local/bin" ] && [ "${USE_GLOBAL:-false}" = "true" ]; then
  TARGET_DIR="/usr/local/bin"
fi
mkdir -p "${TARGET_DIR}"

# 2. Detect OS and Architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

echo "Detected Platform: OS=${OS}, Arch=${ARCH}"

case "${OS}" in
  linux)
    if [ "${ARCH}" = "aarch64" ] || [ "${ARCH}" = "arm64" ]; then
      PACKAGE="cm-linux-arm64.zip"
    else
      PACKAGE="cm-linux-amd64.zip"
    fi
    ;;
  darwin)
    if [ "${ARCH}" = "arm64" ]; then
      PACKAGE="cm-darwin-arm64.zip"
    else
      PACKAGE="cm-darwin-amd64.zip"
    fi
    ;;
  msys*|cygwin*|mingw*)
    if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then
      PACKAGE="cm-windows-arm64.zip"
    else
      PACKAGE="cm-windows-amd64.zip"
    fi
    ;;
  *)
    echo "⚠️  Unknown platform: ${OS}. Defaulting to Linux x86_64 package."
    PACKAGE="cm-linux-amd64.zip"
    ;;
esac

TMP_DIR="$(mktemp -d /tmp/cm-install.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

DOWNLOAD_SUCCESS=false

# 3. Attempt Method A: gcloud CLI (recommended for Google Cloud environments)
if command -v gcloud >/dev/null 2>&1; then
  echo "Attempting download via gcloud artifacts..."
  if gcloud artifacts generic download \
      --project=cmoc-prod \
      --location=us \
      --repository=codemender-cli-production \
      --package=cm \
      --version=stable \
      --name="${PACKAGE}" \
      --destination="${TMP_DIR}/" >/dev/null 2>&1; then
    DOWNLOAD_SUCCESS=true
    echo "✅ Downloaded via gcloud CLI."
  fi
fi

# 4. Attempt Method B: Direct curl download from Artifact Registry
if [ "${DOWNLOAD_SUCCESS}" = "false" ]; then
  DOWNLOAD_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3Astable%3A${PACKAGE}:download?alt=media"
  echo "Downloading ${PACKAGE} via curl..."
  if curl -f -sSL -o "${TMP_DIR}/${PACKAGE}" "${DOWNLOAD_URL}"; then
    DOWNLOAD_SUCCESS=true
    echo "✅ Downloaded via curl."
  fi
fi

if [ "${DOWNLOAD_SUCCESS}" = "false" ]; then
  echo "❌ Error: Failed to download ${PACKAGE}. Please verify network connectivity." >&2
  exit 1
fi

# 5. Extract and install
unzip -q -o "${TMP_DIR}/${PACKAGE}" -d "${TMP_DIR}"
BIN_NAME="cm"
if [ -f "${TMP_DIR}/cm.exe" ]; then
  BIN_NAME="cm.exe"
fi

chmod +x "${TMP_DIR}/${BIN_NAME}"
mv "${TMP_DIR}/${BIN_NAME}" "${TARGET_DIR}/${BIN_NAME}"

echo "✅ Installed CodeMender CLI to ${TARGET_DIR}/${BIN_NAME}"

# 6. Verify installation and path
export PATH="${TARGET_DIR}:${PATH}"
if command -v cm >/dev/null 2>&1; then
  echo "✅ Version: $(cm --version)"
  echo "ℹ️  Testing backend connectivity..."
  cm init --verify || echo "⚠️  Connectivity verification note: ADC authentication may be required (run 'gcloud auth application-default login')."
else
  echo "⚠️  Installed to ${TARGET_DIR}/${BIN_NAME}. Please ensure ${TARGET_DIR} is in your system PATH."
fi

echo "=========================================================="
