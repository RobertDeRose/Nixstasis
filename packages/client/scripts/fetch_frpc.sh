#!/bin/sh

set -eu

TARGET_DIR="build/root-dir/usr/libexec/nixstasis"
ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
PROD_ENV_FILE="${PROD_ENV_FILE:-$ROOT_DIR/prod.env}"
SOURCE_BINARY="${FRPC_SOURCE_BINARY:-}"
SOURCE_SHA256="${FRPC_SOURCE_SHA256:-}"

cleanup() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

fail() {
  echo "$1" >&2
  exit 1
}

ensure_tools() {
  command -v curl >/dev/null 2>&1 || fail "curl is required to fetch the pinned frpc archives"
  command -v tar >/dev/null 2>&1 || fail "tar is required to extract the pinned frpc archives"
  command -v awk >/dev/null 2>&1 || fail "awk is required to parse frpc checksums"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi

  fail "sha256sum or shasum is required to verify the pinned frpc binary"
}

install_binary() {
  source_binary="$1"
  target_binary="$2"
  expected_sha256="$3"

  [ -f "$source_binary" ] || fail "frpc source binary does not exist: $source_binary"

  actual_sha256="$(sha256_file "$source_binary")"
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    fail "frpc checksum mismatch for $source_binary: expected $expected_sha256, got $actual_sha256"
  fi

  cp "$source_binary" "$target_binary"
  chmod 0755 "$target_binary"
}

mkdir -p "$TARGET_DIR"

if [ -n "$SOURCE_BINARY" ]; then
  [ -n "$SOURCE_SHA256" ] || fail "FRPC_SOURCE_SHA256 must be set when FRPC_SOURCE_BINARY is used"
  install_binary "$SOURCE_BINARY" "$TARGET_DIR/frpc_amd64" "$SOURCE_SHA256"
  install_binary "$SOURCE_BINARY" "$TARGET_DIR/frpc_arm64" "$SOURCE_SHA256"
  exit 0
fi

if [ "$(uname -s)" != "Linux" ]; then
  fail "FRPC_SOURCE_BINARY must be set on $(uname -s); tracked prod.env version pins are consumed in Linux release environments"
fi

[ -f "$PROD_ENV_FILE" ] || fail "missing prod env file: $PROD_ENV_FILE"

set -a
. "$PROD_ENV_FILE"
set +a

: "${FRP_VERSION:?FRP_VERSION must be set in $PROD_ENV_FILE}"

FRP_RELEASE_VERSION="$FRP_VERSION"
FRP_BASE_URL="https://github.com/fatedier/frp/releases/download/v${FRP_RELEASE_VERSION}"
FRP_CHECKSUMS_URL="$FRP_BASE_URL/frp_sha256_checksums.txt"
FRP_LINUX_AMD64_ASSET="frp_${FRP_RELEASE_VERSION}_linux_amd64.tar.gz"
FRP_LINUX_ARM64_ASSET="frp_${FRP_RELEASE_VERSION}_linux_arm64.tar.gz"

ensure_tools
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nixstasis-frpc.XXXXXX")
trap cleanup EXIT HUP INT TERM

CHECKSUMS_FILE="$TMP_DIR/frp_sha256_checksums.txt"
curl -fsSL "$FRP_CHECKSUMS_URL" -o "$CHECKSUMS_FILE"

lookup_checksum() {
  asset_name="$1"
  checksum=$(awk -v asset_name="$asset_name" '$2 == asset_name {print $1}' "$CHECKSUMS_FILE")
  [ -n "$checksum" ] || fail "missing checksum for $asset_name in $FRP_CHECKSUMS_URL"
  printf '%s\n' "$checksum"
}

download_archive() {
  arch="$1"
  asset_url="$2"
  expected_sha256="$3"
  archive_name=$(basename "$asset_url")
  archive_path="$TMP_DIR/$archive_name"
  target_binary="$TARGET_DIR/frpc_$arch"

  curl -fsSL "$asset_url" -o "$archive_path"

  actual_sha256="$(sha256_file "$archive_path")"
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    fail "frpc archive checksum mismatch for $asset_url: expected $expected_sha256, got $actual_sha256"
  fi

  frpc_member=$(tar -tzf "$archive_path" | grep '/frpc$' | head -n 1)
  [ -n "$frpc_member" ] || fail "missing frpc in archive: $archive_name"

  tar -xOf "$archive_path" "$frpc_member" > "$target_binary"
  chmod 0755 "$target_binary"
}

download_archive amd64 "$FRP_BASE_URL/$FRP_LINUX_AMD64_ASSET" "$(lookup_checksum "$FRP_LINUX_AMD64_ASSET")"
download_archive arm64 "$FRP_BASE_URL/$FRP_LINUX_ARM64_ASSET" "$(lookup_checksum "$FRP_LINUX_ARM64_ASSET")"
