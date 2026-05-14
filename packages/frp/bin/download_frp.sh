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

ARCHIVE_PATH=$(mktemp "${TMPDIR:-/tmp}/frp.XXXXXX.tar.gz")
CHECKSUMS_PATH=$(mktemp "${TMPDIR:-/tmp}/frp-checksums.XXXXXX")
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/frp-staging.XXXXXX")
cleanup() {
  rm -rf "$ARCHIVE_PATH" "$CHECKSUMS_PATH" "$STAGING_DIR"
}
trap cleanup EXIT HUP INT TERM

curl -fsSL "$CHECKSUMS_URL" -o "$CHECKSUMS_PATH"
expected_sha=$(awk -v asset="$ASSET_NAME" '$2 == asset {print $1}' "$CHECKSUMS_PATH")
[[ -n "$expected_sha" ]] || fail "Missing checksum for $ASSET_NAME."

curl -fsSL "$ASSET_URL" -o "$ARCHIVE_PATH"
actual_sha=$(sha256_file "$ARCHIVE_PATH")
[[ "$actual_sha" = "$expected_sha" ]] || fail "Checksum mismatch for $ASSET_NAME."

tar -xzf "$ARCHIVE_PATH" -C "$STAGING_DIR" --strip-components=1 \
  "frp_${DOWNLOAD_VERSION}_linux_${ARCH}/frpc" \
  "frp_${DOWNLOAD_VERSION}_linux_${ARCH}/frps" \
  "frp_${DOWNLOAD_VERSION}_linux_${ARCH}/LICENSE"

[[ -f "$STAGING_DIR/frpc" ]] || fail "frpc missing from $ASSET_NAME."
[[ -f "$STAGING_DIR/frps" ]] || fail "frps missing from $ASSET_NAME."

upx --lzma -q "$STAGING_DIR/frpc"
upx --lzma -q "$STAGING_DIR/frps"

install -m 0755 "$STAGING_DIR/frpc" "$OUTPUT_DIR/frpc"
install -m 0755 "$STAGING_DIR/frps" "$OUTPUT_DIR/frps"
install -m 0644 "$STAGING_DIR/LICENSE" "$OUTPUT_DIR/../LICENSE"
echo "Download completed"
