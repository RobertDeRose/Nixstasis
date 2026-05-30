#!/bin/bash

set -euo pipefail

# https://github.com/fatedier/frp/releases/download/v0.68.1/frp_0.68.1_linux_arm64.tar.gz
# Inputs
ARCH="$1"
REPO="fatedier/frp"                                # GitHub repository
DOWNLOAD_VERSION=0.68.1
OUTPUT_DIR="${OUTPUT_DIR:-dist/frp}" # Directory to save the binary
TMP_DIR="${OUTPUT_DIR}/.${ARCH}"

fail() {
  echo "Error: $1" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
    return
  fi

  fail "sha256sum or shasum is required"
}

expected_sha256() {
  case "$ARCH" in
    amd64) echo "${FRP_LINUX_AMD64_SHA256:-4a4e88987d39561e1b3b3b23d0ede48a457eebf76a87231999957e870f5f02b6}" ;;
    arm64) echo "${FRP_LINUX_ARM64_SHA256:-e7ad15b0cfe4cf0125df4217778b66cb4426179270967b59900ecb2362d8cd01}" ;;
    *) fail "unsupported frpc architecture: $ARCH" ;;
  esac
}

for tool in curl tar; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

# GitHub Download URL
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${DOWNLOAD_VERSION}/frp_${DOWNLOAD_VERSION}_linux_${ARCH}.tar.gz"
ARCHIVE_PATH="${TMP_DIR}/$(basename "${DOWNLOAD_URL}")"

# Create output directory
rm -rf "$TMP_DIR"
mkdir -p "$OUTPUT_DIR" "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

# Download and verify the binary archive before extracting frpc.
echo "Downloading $(basename "${DOWNLOAD_URL}")"
curl -fsSL "${DOWNLOAD_URL}" -o "$ARCHIVE_PATH"

actual_sha256=$(sha256_file "$ARCHIVE_PATH")
expected_sha256=$(expected_sha256)

if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  fail "checksum mismatch for $(basename "${DOWNLOAD_URL}")"
fi

tar zxvf "$ARCHIVE_PATH" -C "${TMP_DIR}" --strip-components=1 "frp_${DOWNLOAD_VERSION}_linux_${ARCH}/frpc"

if [[ ! -f "${TMP_DIR}/frpc" ]]; then
  fail "frpc missing from $(basename "${DOWNLOAD_URL}")"
fi

chmod +x "${TMP_DIR}/frpc"
if command -v xattr >/dev/null 2>&1; then
  xattr -c "${TMP_DIR}/frpc"
fi

mv -v "${TMP_DIR}/frpc" "${OUTPUT_DIR}/frpc_${ARCH}"
rm -rf "$TMP_DIR"
trap - EXIT HUP INT TERM
echo "Download completed"
