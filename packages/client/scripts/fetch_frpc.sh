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
