#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " 🚀 CodeMender CLI (cm) Cross-Platform Installer"
echo "=========================================================="

# 1. Ensure target bin directory exists
TARGET_DIR="${HOME}/bin"
mkdir -p "${TARGET_DIR}"

# 2. Detect OS and Architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

echo "Detected Platform: OS=${OS}, Arch=${ARCH}"

case "${OS}" in
  linux)
    if [ "${ARCH}" = "x86_64" ] || [ "${ARCH}" = "amd64" ]; then
      PACKAGE="cm-linux-amd64.zip"
    elif [ "${ARCH}" = "aarch64" ] || [ "${ARCH}" = "arm64" ]; then
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
  *)
    echo "⚠️  Unknown platform: ${OS}. Defaulting to Linux x86_64 package."
    PACKAGE="cm-linux-amd64.zip"
    ;;
esac

# 3. Download official CodeMender binary from Google Cloud Artifact Registry
DOWNLOAD_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm:stable:${PACKAGE}:download?alt=media"

echo "Downloading ${PACKAGE} from Artifact Registry..."
TMP_ZIP=$(mktemp /tmp/cm-download.XXXXXX.zip)
TMP_DIR=$(mktemp -d /tmp/cm-extract.XXXXXX)

curl -sSL -o "${TMP_ZIP}" "${DOWNLOAD_URL}"
unzip -q -o "${TMP_ZIP}" -d "${TMP_DIR}"

chmod +x "${TMP_DIR}/cm"
mv "${TMP_DIR}/cm" "${TARGET_DIR}/cm"
rm -rf "${TMP_ZIP}" "${TMP_DIR}"

echo "✅ Installed CodeMender CLI to ${TARGET_DIR}/cm"

# 4. Verify installation
export PATH="${TARGET_DIR}:${PATH}"
if command -v cm >/dev/null 2>&1; then
  echo "✅ Verification Succeeded: $(cm --version)"
else
  echo "⚠️  Installed to ${TARGET_DIR}/cm. Please ensure ${TARGET_DIR} is in your PATH."
fi

echo "=========================================================="
