#!/bin/bash

set -euo pipefail

# Inputs
REPO="fatedier/frp" # GitHub repository

fail() {
  echo "Error: $1" >&2
  exit 1
}

for tool in curl jq tar; do
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

COMPRESS="${COMPRESS:-false}"
OUTPUT_DIR="${OUTPUT_DIR:-build/artifacts/frp/linux_${ARCH}/bin}"

if [[ "$COMPRESS" = "true" ]]; then
  command -v upx >/dev/null 2>&1 || fail "upx is required when COMPRESS=true"
fi

# Check if the version number has exactly four parts
if [[ $(echo "${VERSION}" | tr -cd '.' | wc -c) -eq 3 ]]; then
  # If it has four parts (three dots), chop off the last part
  DOWNLOAD_VERSION="${VERSION%.*}"
else
  DOWNLOAD_VERSION="${VERSION}"
fi

ASSET_NAME="frp_${DOWNLOAD_VERSION}_linux_${ARCH}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/v${DOWNLOAD_VERSION}"
ASSET_URL="$BASE_URL/$ASSET_NAME"
CHECKSUMS_URL="$BASE_URL/frp_sha256_checksums.txt"
case "$ARCH" in
  amd64) PINNED_SHA256="${FRP_LINUX_AMD64_SHA256:-}" ;;
  arm64) PINNED_SHA256="${FRP_LINUX_ARM64_SHA256:-}" ;;
  *) PINNED_SHA256="" ;;
esac

# Create output directory
mkdir -p "$OUTPUT_DIR"

ARCHIVE_PATH=$(mktemp "${TMPDIR:-/tmp}/frp.XXXXXX.tar.gz")
CHECKSUMS_PATH=$(mktemp "${TMPDIR:-/tmp}/frp-checksums.XXXXXX")
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/frp-staging.XXXXXX")
cleanup() {
  rm -rf "$ARCHIVE_PATH" "$CHECKSUMS_PATH" "$STAGING_DIR"
}
trap cleanup EXIT HUP INT TERM

if [[ -n "$PINNED_SHA256" ]]; then
  expected_sha="$PINNED_SHA256"
else
  curl -fsSL "$CHECKSUMS_URL" -o "$CHECKSUMS_PATH"
  expected_sha=$(awk -v asset="$ASSET_NAME" '$2 == asset {print $1}' "$CHECKSUMS_PATH")
  [[ -n "$expected_sha" ]] || fail "Missing checksum for $ASSET_NAME."
fi

curl -fsSL "$ASSET_URL" -o "$ARCHIVE_PATH"
actual_sha=$(sha256_file "$ARCHIVE_PATH")
[[ "$actual_sha" = "$expected_sha" ]] || fail "Checksum mismatch for $ASSET_NAME."

tar -xzf "$ARCHIVE_PATH" -C "$STAGING_DIR" --strip-components=1 \
  "frp_${DOWNLOAD_VERSION}_linux_${ARCH}/frpc" \
  "frp_${DOWNLOAD_VERSION}_linux_${ARCH}/frps" \
  "frp_${DOWNLOAD_VERSION}_linux_${ARCH}/LICENSE"

[[ -f "$STAGING_DIR/frpc" ]] || fail "frpc missing from $ASSET_NAME."
[[ -f "$STAGING_DIR/frps" ]] || fail "frps missing from $ASSET_NAME."

if [[ "$COMPRESS" = "true" ]]; then
  upx --lzma -q "$STAGING_DIR/frpc"
  upx --lzma -q "$STAGING_DIR/frps"
fi

install -m 0755 "$STAGING_DIR/frpc" "$OUTPUT_DIR/frpc"
install -m 0755 "$STAGING_DIR/frps" "$OUTPUT_DIR/frps"
install -m 0644 "$STAGING_DIR/LICENSE" "$OUTPUT_DIR/../LICENSE"
echo "Download completed"
