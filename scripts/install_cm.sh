#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " 🚀 CodeMender CLI (cm) Cross-Platform Installer"
echo "=========================================================="

# 0. Dependency pre-flight checks
for cmd in curl unzip; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "❌ Error: Required tool '${cmd}' is not installed in PATH." >&2
    exit 1
  fi
done

# 1. Determine target binary directory (prefer writable directory in PATH)
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

CM_VERSION="${CM_VERSION:-stable}"

# 2. Check if CodeMender CLI is already installed and matches target version
INSTALLED_CM=""
if command -v cm >/dev/null 2>&1; then
  INSTALLED_CM="$(command -v cm)"
elif [ -x "${TARGET_DIR}/cm" ]; then
  INSTALLED_CM="${TARGET_DIR}/cm"
elif [ -x "${TARGET_DIR}/cm.exe" ]; then
  INSTALLED_CM="${TARGET_DIR}/cm.exe"
fi

if [ -n "${INSTALLED_CM}" ] && [ "${CM_FORCE:-false}" != "true" ]; then
  CURRENT_VERSION="$("${INSTALLED_CM}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  TARGET_VERSION="${CM_VERSION}"

  # If target is "stable", query the lightweight official manifest to resolve semantic version
  if [ "${TARGET_VERSION}" = "stable" ]; then
    MANIFEST_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3Astable%3Astable.json:download?alt=media"
    REMOTE_VERSION="$(curl -fsSL "${MANIFEST_URL}" 2>/dev/null | grep -o '"version": "[^"]*"' | cut -d'"' -f4 || true)"
    if [ -n "${REMOTE_VERSION}" ]; then
      TARGET_VERSION="${REMOTE_VERSION}"
    fi
  fi

  if [ -n "${CURRENT_VERSION}" ] && [ "${CURRENT_VERSION}" = "${TARGET_VERSION}" ]; then
    echo "✅ CodeMender CLI (cm) version ${CURRENT_VERSION} is already installed at ${INSTALLED_CM}."
    echo "   Installation skipped. Set CM_FORCE=true to force re-installation."
    echo "=========================================================="
    exit 0
  else
    echo "ℹ️  Update detected: installed=${CURRENT_VERSION:-unknown} -> target=${TARGET_VERSION}. Proceeding..."
  fi
fi

# 3. Detect OS and architecture, and map to canonical platform key
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "${OS}" in
  linux)
    case "${ARCH}" in
      aarch64|arm64) PACKAGE="cm-linux-arm64.zip";   PLATFORM_KEY="linux-arm64" ;;
      x86_64|amd64)  PACKAGE="cm-linux-amd64.zip";   PLATFORM_KEY="linux-amd64" ;;
      *) echo "❌ Error: Unsupported Linux architecture: ${ARCH}" >&2; exit 1 ;;
    esac
    ;;
  darwin)
    case "${ARCH}" in
      arm64)        PACKAGE="cm-darwin-arm64.zip";  PLATFORM_KEY="darwin-arm64" ;;
      x86_64|amd64) PACKAGE="cm-darwin-amd64.zip";  PLATFORM_KEY="darwin-amd64" ;;
      *) echo "❌ Error: Unsupported macOS architecture: ${ARCH}" >&2; exit 1 ;;
    esac
    ;;
  msys*|cygwin*|mingw*)
    case "${ARCH}" in
      arm64|aarch64) PACKAGE="cm-windows-arm64.zip"; PLATFORM_KEY="windows-arm64" ;;
      x86_64|amd64)  PACKAGE="cm-windows-amd64.zip"; PLATFORM_KEY="windows-amd64" ;;
      *) echo "❌ Error: Unsupported Windows architecture: ${ARCH}" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "❌ Error: Unsupported operating system: ${OS}" >&2
    exit 1
    ;;
esac

echo "Detected Platform: OS=${OS}, Arch=${ARCH}, PlatformKey=${PLATFORM_KEY}, Version=${CM_VERSION}"

TMP_DIR="$(mktemp -d /tmp/cm-install.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

DOWNLOAD_SUCCESS=false

# 4. Method A: Direct fast download via curl (Primary)
DOWNLOAD_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3A${CM_VERSION}%3A${PACKAGE}:download?alt=media"
echo "Downloading ${PACKAGE} via curl..."
if curl -f -sSL -o "${TMP_DIR}/${PACKAGE}" "${DOWNLOAD_URL}"; then
  DOWNLOAD_SUCCESS=true
  echo "✅ Downloaded via curl."
fi

# 5. Method B: Fallback download via gcloud CLI (Backup for VPC-SC / IAM restricted networks)
if [ "${DOWNLOAD_SUCCESS}" = "false" ] && command -v gcloud >/dev/null 2>&1; then
  echo "⚠️  Direct curl download failed. Attempting fallback via gcloud artifacts..."
  if gcloud artifacts generic download \
      --project=cmoc-prod \
      --location=us \
      --repository=codemender-cli-production \
      --package=cm \
      --version="${CM_VERSION}" \
      --name="${PACKAGE}" \
      --destination="${TMP_DIR}/" >/dev/null 2>&1; then
    DOWNLOAD_SUCCESS=true
    echo "✅ Downloaded via gcloud CLI fallback."
  fi
fi

if [ "${DOWNLOAD_SUCCESS}" = "false" ]; then
  echo "❌ Error: Failed to download ${PACKAGE} via both curl and gcloud. Please verify network connectivity." >&2
  exit 1
fi

# 6. Extract archive
unzip -q -o "${TMP_DIR}/${PACKAGE}" -d "${TMP_DIR}"
BIN_NAME="cm"
if [ -f "${TMP_DIR}/cm.exe" ]; then
  BIN_NAME="cm.exe"
fi
BIN_PATH="${TMP_DIR}/${BIN_NAME}"

# 7. Integrity and authenticity verification (SHA-256)
# Note: Google's release manifest registers the SHA-256 of the extracted binary, not the ZIP archive.
HASH_CMD=""
if command -v shasum >/dev/null 2>&1; then
  HASH_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_CMD="sha256sum"
fi

if [ -n "${HASH_CMD}" ]; then
  ACTUAL_BIN_SHA="$(${HASH_CMD} "${BIN_PATH}" | awk '{print $1}')"
  echo "🔒 Binary SHA-256 (${BIN_NAME}): ${ACTUAL_BIN_SHA}"

  # Priority 1: Caller-provided out-of-band SHA-256 (recommended for pinned CI/CD pipelines)
  if [ -n "${CM_SHA256:-}" ]; then
    if [ "${ACTUAL_BIN_SHA}" != "${CM_SHA256}" ]; then
      echo "❌ Error: SHA-256 checksum mismatch!" >&2
      echo "   Expected: ${CM_SHA256}" >&2
      echo "   Actual:   ${ACTUAL_BIN_SHA}" >&2
      exit 1
    fi
    echo "✅ SHA-256 verified against user-provided CM_SHA256."

  # Priority 2: In-band verification against official release manifest (ensures transport integrity)
  elif [ "${CM_SKIP_VERIFY:-false}" != "true" ]; then
    MANIFEST_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3A${CM_VERSION}%3A${CM_VERSION}.json:download?alt=media"
    MANIFEST_FILE="${TMP_DIR}/manifest.json"

    if curl -fsSL -o "${MANIFEST_FILE}" "${MANIFEST_URL}" 2>/dev/null; then
      EXPECTED_SHA="$(grep -o "\"${PLATFORM_KEY}\": \"[^\"]*\"" "${MANIFEST_FILE}" | cut -d'"' -f4 || true)"
      MANIFEST_VERSION="$(grep -o '"version": "[^"]*"' "${MANIFEST_FILE}" | cut -d'"' -f4 || true)"

      if [ -n "${MANIFEST_VERSION}" ]; then
        echo "ℹ️  Official release manifest version: ${MANIFEST_VERSION}"
      fi

      if [ -n "${EXPECTED_SHA}" ]; then
        if [ "${ACTUAL_BIN_SHA}" != "${EXPECTED_SHA}" ]; then
          echo "❌ Error: Binary SHA-256 does not match official release manifest!" >&2
          echo "   Expected: ${EXPECTED_SHA}" >&2
          echo "   Actual:   ${ACTUAL_BIN_SHA}" >&2
          exit 1
        fi
        echo "✅ SHA-256 verified against official release manifest."
      fi
    else
      echo "ℹ️  Note: Release manifest could not be retrieved; skipped automatic checksum verification."
    fi
  fi
fi

# 8. Install binary to target directory
chmod +x "${BIN_PATH}"
mv "${BIN_PATH}" "${TARGET_DIR}/${BIN_NAME}"
echo "✅ Installed CodeMender CLI to ${TARGET_DIR}/${BIN_NAME}"

# 9. Verify installation and path
export PATH="${TARGET_DIR}:${PATH}"
if command -v cm >/dev/null 2>&1; then
  echo "✅ Installed Version: $(cm --version)"
  echo "ℹ️  Testing backend connectivity..."
  HOME="${TMP_DIR}" cm init --verify || echo "⚠️  Connectivity verification note: ADC authentication may be required (run 'gcloud auth application-default login')."
else
  echo "⚠️  Installed to ${TARGET_DIR}/${BIN_NAME}. Please ensure ${TARGET_DIR} is in your system PATH."
fi

echo "=========================================================="
