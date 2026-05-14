#!/bin/bash

set -euo pipefail

# Inputs
REPO="fatedier/frp"                     # GitHub repository
OUTPUT_DIR="build/root-dir/opt/frp/bin" # Directory to save the binary

fail() {
  echo "Error: $1" >&2
  exit 1
}

for tool in curl jq tar upx; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

: "${VERSION:?VERSION is required}"
: "${ARCH:?ARCH is required}"

# Check if the version number has exactly four parts
if [[ $(echo "${VERSION}" | tr -cd '.' | wc -c) -eq 3 ]]; then
  # If it has four parts (three dots), chop off the last part
  DOWNLOAD_VERSION="${VERSION%.*}"
else
  DOWNLOAD_VERSION="${VERSION}"
fi

# GitHub API URL for releases
API_URL="https://api.github.com/repos/${REPO}/releases/tags/v${DOWNLOAD_VERSION}"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get release data
RELEASE_DATA=$(curl -fsS "$API_URL")

# Find the download URL for the binary
ASSET_URL=$(echo "$RELEASE_DATA" | jq -r \
  --arg ARCH "$ARCH" '.assets[] | select((.name | contains($ARCH)) and (.name | contains("linux"))) | .browser_download_url')

if [[ -z ${ASSET_URL} ]]; then
  fail "No asset found for architecture $ARCH in version $VERSION."
fi

# Download the binary
echo "Downloading $(basename "${ASSET_URL}")"
if curl -sSL "${ASSET_URL}" | tar zxvf - -C "${OUTPUT_DIR}" --strip-components=1 --wildcards '*frp*'; then
  chmod +x "${OUTPUT_DIR}/frpc"
  chmod +x "${OUTPUT_DIR}/frps"
  upx --lzma -q "${OUTPUT_DIR}/frpc"
  upx --lzma -q "${OUTPUT_DIR}/frps"
  rm -f "${OUTPUT_DIR}/"*.toml
  mv "${OUTPUT_DIR}/LICENSE" "${OUTPUT_DIR}/.."
  echo "Download completed"
else
  echo "Download failed"
  exit 1
fi
