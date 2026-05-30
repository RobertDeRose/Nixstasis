#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
ENV_FILE="${1:-$COMPOSE_DIR/.env}"
CADDYFILE="$COMPOSE_DIR/caddy/Caddyfile"

fail() {
  echo "$1" >&2
  exit 1
}

env_value() {
  name="$1"

  awk -F= -v name="$name" '
    $1 == name {
      value = substr($0, length(name) + 2)
      print value
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$ENV_FILE"
}

require_env_value() {
  name="$1"
  value=$(env_value "$name" || true)

  if [ -z "$value" ]; then
    fail "missing required env value: $name"
  fi

  if [ "$value" = "*" ]; then
    fail "$name must be least-privilege and cannot be wildcard"
  fi
}

require_exact_env_value() {
  name="$1"
  expected="$2"
  value=$(env_value "$name" || true)

  if [ -z "$value" ]; then
    fail "missing required env value: $name"
  fi

  if [ "$value" != "$expected" ]; then
    fail "$name must be $expected for supported Compose deployment, got: $value"
  fi
}

require_caddy_text() {
  pattern="$1"
  grep -En "$pattern" "$CADDYFILE" >/dev/null || fail "missing Caddy policy text: $pattern"
}

reject_caddy_text() {
  pattern="$1"
  if grep -En "$pattern" "$CADDYFILE" >/dev/null; then
    fail "forbidden Caddy policy text: $pattern"
  fi
}

require_wildcard_authorize_before_proxy() {
  awk '
    /^\*\.\{\$BASE_DOMAIN\} \{/ { in_wildcard = 1; authorized = 0; saw_wildcard = 1; next }
    in_wildcard && /^}/ {
      if (!authorized) {
        exit 1
      }
      in_wildcard = 0
    }
    in_wildcard && /authorize with entra_policy/ { authorized = 1 }
    in_wildcard && /reverse_proxy frps:\{\$FRPS_HTTP_PORT\}/ && !authorized { exit 1 }
    END { if (!saw_wildcard) exit 1 }
  ' "$CADDYFILE" || fail "wildcard FRP host must authorize with entra_policy before proxying"
}

if command -v docker >/dev/null 2>&1; then
  COMPOSE_VARIANT="docker"
elif command -v container-compose >/dev/null 2>&1; then
  COMPOSE_VARIANT="container-compose"
else
  fail "docker compose or container-compose is required"
fi

compose_build() {
  if [ "$COMPOSE_VARIANT" = "docker" ]; then
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build "$@"
    return
  fi

  RENDERED_COMPOSE_FILE=$(mktemp "$COMPOSE_DIR/.nixstasis-compose.XXXXXX.yml")
  trap 'rm -f "$RENDERED_COMPOSE_FILE"' EXIT HUP INT TERM
  "$COMPOSE_DIR/scripts/render_compose.sh" "$ENV_FILE" "$RENDERED_COMPOSE_FILE"
  container-compose build -f "$RENDERED_COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

if [ ! -f "$ENV_FILE" ]; then
  fail "missing env file: $ENV_FILE"
fi

require_env_value AUTHORIZED_ROLES
require_env_value AUTHORIZED_GROUPS
require_env_value NIXSTASIS_VIEWER_GROUPS
require_env_value NIXSTASIS_OPERATOR_GROUPS
require_env_value NIXSTASIS_ADMIN_GROUPS
require_exact_env_value PORT 4000
require_exact_env_value PHOENIX_BIND_HOST 127.0.0.1
require_exact_env_value CADDY_CONFIG ./caddy/Caddyfile
require_caddy_text 'ask http://nixstasis:\{\$PORT\}/api/v1/check_domain'
require_caddy_text 'reverse_proxy nixstasis:\{\$PORT\}'
reject_caddy_text 'ask http://nixstasis:4000/api/v1/check_domain'
reject_caddy_text 'reverse_proxy nixstasis:4000'
require_caddy_text 'allow roles \{\$AUTHORIZED_ROLES\}'
require_caddy_text 'allow groups \{\$AUTHORIZED_GROUPS\}'
require_caddy_text 'match groups \{\$NIXSTASIS_VIEWER_GROUPS\}'
require_caddy_text 'action add role nixstasis/viewer'
require_caddy_text 'match groups \{\$NIXSTASIS_OPERATOR_GROUPS\}'
require_caddy_text 'action add role nixstasis/operator'
require_caddy_text 'match groups \{\$NIXSTASIS_ADMIN_GROUPS\}'
require_caddy_text 'action add role nixstasis/admin'
reject_caddy_text 'allow roles \*'
reject_caddy_text 'allow groups \*'
require_wildcard_authorize_before_proxy

compose_build >/dev/null

for service in caddy nixstasis frps postgres; do
  grep -Eq "^[[:space:]]{2}${service}:$" "$COMPOSE_FILE"
done

echo "compose stack validation passed"
