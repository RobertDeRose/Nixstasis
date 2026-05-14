#!/bin/sh

set -eu

# Development helper only. Production Caddy images are built with the Dockerfile,
# which pins the Caddy builder and runner images by digest.

OUTPUT_DIR="${OUTPUT_DIR:-build/root-dir/opt/caddy/bin}"
ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
PROD_ENV_FILE="${PROD_ENV_FILE:-$ROOT_DIR/prod.env}"

if [ -f "$PROD_ENV_FILE" ]; then
  set -a
  . "$PROD_ENV_FILE"
  set +a
fi

CADDY_VERSION="${CADDY_VERSION:-2.11.2}"
CADDY_SECURITY_VERSION="${CADDY_SECURITY_VERSION:-v1.1.62}"

mkdir -p "$OUTPUT_DIR"

xcaddy build "v$CADDY_VERSION" --with "github.com/greenpau/caddy-security@$CADDY_SECURITY_VERSION" --output "$OUTPUT_DIR/caddy"
