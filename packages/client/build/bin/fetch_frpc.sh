#!/bin/bash

# https://github.com/fatedier/frp/releases/download/v0.68.1/frp_0.68.1_linux_arm64.tar.gz
# Inputs
ARCH="$1"
REPO="fatedier/frp"                                # GitHub repository
DOWNLOAD_VERSION=0.68.1
OUTPUT_DIR="dist/frp" # Directory to save the binary
TMP_DIR="${OUTPUT_DIR}/.${ARCH}"

# GitHub Download URL
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${DOWNLOAD_VERSION}/frp_${DOWNLOAD_VERSION}_linux_${ARCH}.tar.gz"

# Create output directory
rm -rf "$TMP_DIR"
mkdir -p "$OUTPUT_DIR" "$TMP_DIR"

# Download the binary
echo "Downloading $(basename "${DOWNLOAD_URL}")"
if curl -sSL "${DOWNLOAD_URL}" | tar zxvf - -C "${TMP_DIR}" --wildcards '*/frpc' --strip-components=1; then
  chmod +x "${TMP_DIR}/frpc"
  if command -v xattr >/dev/null 2>&1; then
    xattr -c "${TMP_DIR}/frpc"
  fi
  mv -v "${TMP_DIR}/frpc" "${OUTPUT_DIR}/frpc_${ARCH}"
  rm -rf "$TMP_DIR"
  echo "Download completed"
else
  echo "Download failed"
  exit 1
fi
