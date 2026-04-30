#!/bin/sh

set -eu

TARGET_DIR="build/root-dir/usr/libexec/nixstasis"
SOURCE_BINARY="${FRPC_SOURCE_BINARY:-}"

mkdir -p "$TARGET_DIR"

if [ -z "$SOURCE_BINARY" ]; then
  echo "FRPC_SOURCE_BINARY must point to a pinned frpc binary" >&2
  exit 1
fi

install -m 0755 "$SOURCE_BINARY" "$TARGET_DIR/frpc"
