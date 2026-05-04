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

env_value() {
  key="$1"
  value=$(
    awk -v key="$key" '
      /^[[:space:]]*(#|$)/ { next }
      {
        line = $0
        sub(/^[[:space:]]*export[[:space:]]+/, "", line)
        if (line !~ "^[[:space:]]*" key "[[:space:]]*=") next
        sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if ((line ~ /^".*"$/) || (line ~ /^'\''.*'\''$/)) {
          line = substr(line, 2, length(line) - 2)
        }
        print line
        found = 1
        exit
      }
      END { if (!found) exit 1 }
    ' "$ENV_FILE"
  ) || return 1

  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

NIXSTASIS_SERVER_IMAGE_REF=$(env_value NIXSTASIS_SERVER_IMAGE_REF) || {
  echo "NIXSTASIS_SERVER_IMAGE_REF must be set" >&2
  exit 1
}

NIXSTASIS_CADDY_IMAGE_REF=$(env_value NIXSTASIS_CADDY_IMAGE_REF) || {
  echo "NIXSTASIS_CADDY_IMAGE_REF must be set" >&2
  exit 1
}

NIXSTASIS_FRPS_IMAGE_REF=$(env_value NIXSTASIS_FRPS_IMAGE_REF) || {
  echo "NIXSTASIS_FRPS_IMAGE_REF must be set" >&2
  exit 1
}

awk \
  -v server_ref="$NIXSTASIS_SERVER_IMAGE_REF" \
  -v caddy_ref="$NIXSTASIS_CADDY_IMAGE_REF" \
  -v frps_ref="$NIXSTASIS_FRPS_IMAGE_REF" \
  '{
    gsub(/\$\{NIXSTASIS_SERVER_IMAGE_REF\}/, server_ref)
    gsub(/\$\{NIXSTASIS_CADDY_IMAGE_REF\}/, caddy_ref)
    gsub(/\$\{NIXSTASIS_FRPS_IMAGE_REF\}/, frps_ref)
    print
  }' "$COMPOSE_FILE" > "$OUTPUT_FILE"
