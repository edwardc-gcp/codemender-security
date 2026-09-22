#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " 🚀 CodeMender CLI (cm) Cross-Platform Installer"
echo "=========================================================="

# 0. Dependency pre-flight checks (P1-7)
for cmd in curl unzip; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "❌ Error: Required tool '${cmd}' is not installed in PATH." >&2
    exit 1
  fi
done

# 1. Determine target binary directory idempotently (prefer writable dir in PATH) (P1-4)
if [ -n "${CM_INSTALL_DIR:-}" ]; then
  TARGET_DIR="${CM_INSTALL_DIR}"
elif [ -w "/usr/local/bin" ]; then
  TARGET_DIR="/usr/local/bin"
elif [[ ":${PATH}:" == *":${HOME}/.local/bin:"* ]]; then
  TARGET_DIR="${HOME}/.local/bin"
else
  TARGET_DIR="${HOME}/bin"
fi
mkdir -p "${TARGET_DIR}"

# 2. Detect OS and Architecture (fail fast on unsupported platforms) (P1-7)
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
CM_VERSION="${CM_VERSION:-stable}"

echo "Detected Platform: OS=${OS}, Arch=${ARCH}, Version=${CM_VERSION}"

case "${OS}" in
  linux)
    case "${ARCH}" in
      aarch64|arm64) PACKAGE="cm-linux-arm64.zip" ;;
      x86_64|amd64)  PACKAGE="cm-linux-amd64.zip" ;;
      *) echo "❌ Error: Unsupported Linux architecture: ${ARCH}" >&2; exit 1 ;;
    esac
    ;;
  darwin)
    case "${ARCH}" in
      arm64)        PACKAGE="cm-darwin-arm64.zip" ;;
      x86_64|amd64) PACKAGE="cm-darwin-amd64.zip" ;;
      *) echo "❌ Error: Unsupported macOS architecture: ${ARCH}" >&2; exit 1 ;;
    esac
    ;;
  msys*|cygwin*|mingw*)
    case "${ARCH}" in
      arm64|aarch64) PACKAGE="cm-windows-arm64.zip" ;;
      x86_64|amd64)  PACKAGE="cm-windows-amd64.zip" ;;
      *) echo "❌ Error: Unsupported Windows architecture: ${ARCH}" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "❌ Error: Unsupported operating system: ${OS}" >&2
    exit 1
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
      --version="${CM_VERSION}" \
      --name="${PACKAGE}" \
      --destination="${TMP_DIR}/" >/dev/null 2>&1; then
    DOWNLOAD_SUCCESS=true
    echo "✅ Downloaded via gcloud CLI."
  fi
fi

# 4. Attempt Method B: Direct curl download from Artifact Registry
if [ "${DOWNLOAD_SUCCESS}" = "false" ]; then
  DOWNLOAD_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3A${CM_VERSION}%3A${PACKAGE}:download?alt=media"
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

# 5. Integrity / SHA-256 Verification (P0-6)
if command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(shasum -a 256 "${TMP_DIR}/${PACKAGE}" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(sha256sum "${TMP_DIR}/${PACKAGE}" | awk '{print $1}')"
else
  ACTUAL_SHA256="unavailable"
fi
echo "🔒 Archive SHA-256 (${PACKAGE}): ${ACTUAL_SHA256}"

if [ -n "${CM_SHA256:-}" ]; then
  if [ "${ACTUAL_SHA256}" != "${CM_SHA256}" ]; then
    echo "❌ Error: SHA-256 checksum mismatch! Expected ${CM_SHA256}, got ${ACTUAL_SHA256}." >&2
    exit 1
  fi
  echo "✅ SHA-256 checksum verified."
fi

# 6. Extract and install
unzip -q -o "${TMP_DIR}/${PACKAGE}" -d "${TMP_DIR}"
BIN_NAME="cm"
if [ -f "${TMP_DIR}/cm.exe" ]; then
  BIN_NAME="cm.exe"
fi

chmod +x "${TMP_DIR}/${BIN_NAME}"
mv "${TMP_DIR}/${BIN_NAME}" "${TARGET_DIR}/${BIN_NAME}"

echo "✅ Installed CodeMender CLI to ${TARGET_DIR}/${BIN_NAME}"

# 7. Verify installation and path (isolated in TMP_DIR so workspace is untouched)
export PATH="${TARGET_DIR}:${PATH}"
if command -v cm >/dev/null 2>&1; then
  echo "✅ Version: $(cm --version)"
  echo "ℹ️  Testing backend connectivity..."
  HOME="${TMP_DIR}" cm init --verify || echo "⚠️  Connectivity verification note: ADC authentication may be required (run 'gcloud auth application-default login')."
else
  echo "⚠️  Installed to ${TARGET_DIR}/${BIN_NAME}. Please ensure ${TARGET_DIR} is in your system PATH."
fi

echo "=========================================================="
