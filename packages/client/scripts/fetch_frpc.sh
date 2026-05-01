#!/bin/sh

set -eu

TARGET_DIR="build/root-dir/usr/libexec/nixstasis"
TARGET_BINARY="$TARGET_DIR/frpc"
SOURCE_BINARY="${FRPC_SOURCE_BINARY:-}"
SOURCE_SHA256="${FRPC_SOURCE_SHA256:-}"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi

  echo "sha256sum or shasum is required to verify the pinned frpc binary" >&2
  exit 1
}

if [ -z "$SOURCE_BINARY" ]; then
  echo "FRPC_SOURCE_BINARY must point to a pinned frpc binary" >&2
  exit 1
fi

if [ -z "$SOURCE_SHA256" ]; then
  echo "FRPC_SOURCE_SHA256 must be set to the expected frpc checksum" >&2
  exit 1
fi

if [ ! -f "$SOURCE_BINARY" ]; then
  echo "FRPC_SOURCE_BINARY does not exist: $SOURCE_BINARY" >&2
  exit 1
fi

ACTUAL_SHA256="$(sha256_file "$SOURCE_BINARY")"
if [ "$ACTUAL_SHA256" != "$SOURCE_SHA256" ]; then
  echo "frpc checksum mismatch: expected $SOURCE_SHA256, got $ACTUAL_SHA256" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
install -m 0755 "$SOURCE_BINARY" "$TARGET_BINARY"
