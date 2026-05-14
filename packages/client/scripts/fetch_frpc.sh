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
  command -v cp >/dev/null 2>&1 || fail "cp is required to stage frpc binaries"
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
FRP_FETCH_SCRIPT="$ROOT_DIR/packages/frp/bin/download_frp.sh"

ensure_tools
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nixstasis-frpc.XXXXXX")
trap cleanup EXIT HUP INT TERM

fetch_archive() {
  arch="$1"
  artifact_dir="$TMP_DIR/frp-$arch"
  target_binary="$TARGET_DIR/frpc_$arch"

  VERSION="$FRP_RELEASE_VERSION" ARCH="$arch" COMPRESS=false OUTPUT_DIR="$artifact_dir" \
    "$FRP_FETCH_SCRIPT"
  cp "$artifact_dir/frpc" "$target_binary"
  chmod 0755 "$target_binary"
}

fetch_archive amd64
fetch_archive arm64
