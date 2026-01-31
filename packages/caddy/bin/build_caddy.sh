#!/bin/bash

# Inputs
REPO="caddyserver/xcaddy"                 # GitHub repository
OUTPUT_DIR="build/root-dir/opt/caddy/bin" # Directory to save the binary

# GitHub API URL for releases
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get release data
RELEASE_DATA=$(curl -s "$API_URL")

# Find the download URL for the binary
ASSET_URL=$(echo "$RELEASE_DATA" | jq -r \
  --arg ARCH "$ARCH" '.assets[]
  | select((.name | contains($ARCH)) and (.name | contains("linux")) and (.name | contains(".tar")))
  | .browser_download_url')

if [[ -z ${ASSET_URL} ]]; then
  echo "Error: No asset found for architecture $ARCH in version $VERSION."
  exit 1
fi

# Download the binary
echo "Downloading $(basename "${ASSET_URL}")"
if curl -sSL "${ASSET_URL}" | tar zxvf - -C bin --wildcards 'xcaddy'; then
  chmod +x "bin/xcaddy"
  echo "Download completed"
else
  echo "Download failed"
  exit 1
fi

# Check if the version number has exactly four parts
if [[ $(echo "${VERSION}" | tr -cd '.' | wc -c) -eq 3 ]]; then
  # If it has four parts (three dots), chop off the last part
  BUILD_VERSION="${VERSION%.*}"
else
  BUILD_VERSION="${VERSION}"
fi

bin/xcaddy build "v${BUILD_VERSION}" --with github.com/greenpau/caddy-security --output "${OUTPUT_DIR}/caddy"
upx --lzma -q "${OUTPUT_DIR}/caddy"
