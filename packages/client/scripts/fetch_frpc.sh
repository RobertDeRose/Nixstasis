#!/bin/bash

# https://github.com/fatedier/frp/releases/download/v0.68.1/frp_0.68.1_linux_arm64.tar.gz
# Inputs
REPO="fatedier/frp"                                # GitHub repository
OUTPUT_DIR="build/root-dir/usr/libexec/nixstasis/" # Directory to save the binary
DOWNLOAD_VERSION=0.68.1
ARCH="$1"

# GitHub Download URL
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${DOWNLOAD_VERSION}/frp_${DOWNLOAD_VERSION}_linux_${ARCH}.tar.gz"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Download the binary
echo "Downloading $(basename "${DOWNLOAD_URL}")"
if curl -sSL "${DOWNLOAD_URL}" | tar zxvf - -C "${OUTPUT_DIR}" --wildcards '*/frpc' --strip-components=1; then
  chmod +x "${OUTPUT_DIR}/frpc"
  echo "Download completed"
else
  echo "Download failed"
  exit 1
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
