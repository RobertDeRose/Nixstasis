#!/bin/sh

set -eu

OUTPUT_DIR="${OUTPUT_DIR:-build/root-dir/opt/caddy/bin}"
CADDY_VERSION="${CADDY_VERSION:-v2.10.2}"

mkdir -p "$OUTPUT_DIR"

xcaddy build "$CADDY_VERSION" --with github.com/greenpau/caddy-security --output "$OUTPUT_DIR/caddy"
