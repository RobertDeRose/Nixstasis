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

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi

  fail "sha256sum or shasum is required"
}

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
ASSET_NAME="frp_${DOWNLOAD_VERSION}_linux_${ARCH}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/v${DOWNLOAD_VERSION}"
CHECKSUMS_URL="$BASE_URL/frp_sha256_checksums.txt"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get release data
RELEASE_DATA=$(curl -fsS "$API_URL")

# Find the download URL for the binary
ASSET_URL=$(echo "$RELEASE_DATA" | jq -r \
  --arg ASSET_NAME "$ASSET_NAME" '.assets[] | select(.name == $ASSET_NAME) | .browser_download_url')

if [[ -z ${ASSET_URL} ]]; then
  fail "No asset found for $ASSET_NAME in version $VERSION."
fi

if [[ $(echo "$ASSET_URL" | wc -l | tr -d ' ') -ne 1 ]]; then
  fail "Expected exactly one asset URL for $ASSET_NAME."
fi

# Download the binary
echo "Downloading $(basename "${ASSET_URL}")"
ARCHIVE_PATH=$(mktemp "${TMPDIR:-/tmp}/frp.XXXXXX.tar.gz")
CHECKSUMS_PATH=$(mktemp "${TMPDIR:-/tmp}/frp-checksums.XXXXXX")
cleanup() {
  rm -f "$ARCHIVE_PATH" "$CHECKSUMS_PATH"
}
trap cleanup EXIT HUP INT TERM

curl -fsSL "$CHECKSUMS_URL" -o "$CHECKSUMS_PATH"
expected_sha=$(awk -v asset="$ASSET_NAME" '$2 == asset {print $1}' "$CHECKSUMS_PATH")
[[ -n "$expected_sha" ]] || fail "Missing checksum for $ASSET_NAME."

curl -fsSL "$ASSET_URL" -o "$ARCHIVE_PATH"
actual_sha=$(sha256_file "$ARCHIVE_PATH")
[[ "$actual_sha" = "$expected_sha" ]] || fail "Checksum mismatch for $ASSET_NAME."

if tar zxvf "$ARCHIVE_PATH" -C "${OUTPUT_DIR}" --strip-components=1 --wildcards '*frp*'; then
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
