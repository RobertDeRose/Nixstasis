#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_FILE="$ROOT_DIR/deploy/compose/docker-compose.yml"
ENV_FILE="${1:-$ROOT_DIR/deploy/compose/.env}"
OUTPUT_FILE="${2:-}"

if [ -z "$OUTPUT_FILE" ]; then
  echo "output file path is required" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

: "${NIXSTASIS_SERVER_IMAGE_REF:?NIXSTASIS_SERVER_IMAGE_REF must be set}"
: "${NIXSTASIS_CADDY_IMAGE_REF:?NIXSTASIS_CADDY_IMAGE_REF must be set}"

awk \
  -v server_ref="$NIXSTASIS_SERVER_IMAGE_REF" \
  -v caddy_ref="$NIXSTASIS_CADDY_IMAGE_REF" \
  '{
    gsub(/\$\{NIXSTASIS_SERVER_IMAGE_REF\}/, server_ref)
    gsub(/\$\{NIXSTASIS_CADDY_IMAGE_REF\}/, caddy_ref)
    print
  }' "$COMPOSE_FILE" > "$OUTPUT_FILE"
