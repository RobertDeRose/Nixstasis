#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
ENV_EXAMPLE="$COMPOSE_DIR/.env.example"
CADDYFILE="$COMPOSE_DIR/caddy/Caddyfile"
FRPS_TOML="$COMPOSE_DIR/frps/frps.toml"
COMPOSE_README="$COMPOSE_DIR/README.md"
SERVER_RUNTIME="$ROOT_DIR/packages/server/config/runtime.exs"
SERVER_README="$ROOT_DIR/packages/server/README.md"
CLIENT_README="$ROOT_DIR/packages/client/README.md"
CLIENT_CONFIG_TEMPLATE="$ROOT_DIR/packages/client/build/root-dir/usr/share/nixstasis/config.example.yaml"
CLIENT_FRPC_TEMPLATE="$ROOT_DIR/packages/client/build/root-dir/etc/nixstasis/frpc.toml"
CONTRACT_DOC="$ROOT_DIR/specs/013-nixstasis-packaging-migration/contracts/compose-runtime-contract.md"

fail() {
  echo "$1" >&2
  exit 1
}

require_text() {
  file="$1"
  pattern="$2"

  rg -n "$pattern" "$file" >/dev/null || fail "missing contract text in $file: $pattern"
}

for file in \
  "$ENV_EXAMPLE" \
  "$CADDYFILE" \
  "$FRPS_TOML" \
  "$COMPOSE_README" \
  "$SERVER_RUNTIME" \
  "$SERVER_README" \
  "$CLIENT_README" \
  "$CLIENT_CONFIG_TEMPLATE" \
  "$CLIENT_FRPC_TEMPLATE" \
  "$CONTRACT_DOC"; do
  [ -f "$file" ] || fail "missing required file: $file"
done

require_text "$ENV_EXAMPLE" '^DATABASE_URL='
require_text "$ENV_EXAMPLE" '^SECRET_KEY_BASE='
require_text "$ENV_EXAMPLE" '^PHX_HOST='
require_text "$ENV_EXAMPLE" '^PORT=4000$'
require_text "$ENV_EXAMPLE" '^BASE_DOMAIN='
require_text "$ENV_EXAMPLE" '^CLIENT_ID='
require_text "$ENV_EXAMPLE" '^CLIENT_SECRET='
require_text "$ENV_EXAMPLE" '^TENANT_ID='
require_text "$ENV_EXAMPLE" '^JWT_KEY='
require_text "$ENV_EXAMPLE" '^FRPS_BIND_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_HTTP_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_DASHBOARD_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_TCPMUX_PORT='

require_text "$CADDYFILE" 'check_domain'
require_text "$CADDYFILE" 'auth\.\{\$BASE_DOMAIN\}'
require_text "$CADDYFILE" 'nixstasis\.\{\$BASE_DOMAIN\}'
require_text "$CADDYFILE" 'frp-admin\.\{\$BASE_DOMAIN\}'
require_text "$FRPS_TOML" '__BASE_DOMAIN__'
require_text "$FRPS_TOML" '__FRPS_BIND_PORT__'
require_text "$FRPS_TOML" '__FRPS_HTTP_PORT__'
require_text "$FRPS_TOML" '__FRPS_DASHBOARD_PORT__'
require_text "$FRPS_TOML" '__FRPS_TCPMUX_PORT__'

require_text "$SERVER_RUNTIME" 'required_env!\("DATABASE_URL"\)'
require_text "$SERVER_RUNTIME" 'required_env!\("SECRET_KEY_BASE"\)'
require_text "$SERVER_RUNTIME" 'required_env!\("PHX_HOST"\)'
require_text "$SERVER_RUNTIME" 'required_env!\("BASE_DOMAIN"\)'
require_text "$SERVER_RUNTIME" 'Deployment\.port\(\)'

require_text "$COMPOSE_README" 'DATABASE_URL'
require_text "$COMPOSE_README" 'BASE_DOMAIN'
require_text "$COMPOSE_README" 'check_domain'
require_text "$COMPOSE_README" 'bundled PostgreSQL'
require_text "$COMPOSE_README" 'external PostgreSQL'

require_text "$SERVER_README" 'DATABASE_URL'
require_text "$SERVER_README" 'SECRET_KEY_BASE'
require_text "$SERVER_README" 'PHX_HOST'
require_text "$SERVER_README" 'PORT'
require_text "$SERVER_README" 'BASE_DOMAIN'
require_text "$SERVER_README" 'CLIENT_ID'
require_text "$SERVER_README" 'CLIENT_SECRET'
require_text "$SERVER_README" 'TENANT_ID'
require_text "$SERVER_README" 'JWT_KEY'
require_text "$SERVER_README" 'FRPS_BIND_PORT'
require_text "$SERVER_README" 'FRPS_HTTP_PORT'
require_text "$SERVER_README" 'FRPS_DASHBOARD_PORT'
require_text "$SERVER_README" 'FRPS_TCPMUX_PORT'

require_text "$CLIENT_README" 'https://nixstasis\.example\.com'
require_text "$CLIENT_README" '/etc/nixstasis/config\.yaml'
require_text "$CLIENT_CONFIG_TEMPLATE" 'https://nixstasis\.example\.com'
require_text "$CLIENT_FRPC_TEMPLATE" 'serverAddr = "nixstasis\.example\.com"'
require_text "$CLIENT_FRPC_TEMPLATE" 'atom-<normalized-device-id>\.<base-domain>'

require_text "$CONTRACT_DOC" 'DATABASE_URL'
require_text "$CONTRACT_DOC" 'SECRET_KEY_BASE'
require_text "$CONTRACT_DOC" 'PHX_HOST'
require_text "$CONTRACT_DOC" 'PORT'
require_text "$CONTRACT_DOC" 'BASE_DOMAIN'
require_text "$CONTRACT_DOC" 'CLIENT_ID'
require_text "$CONTRACT_DOC" 'CLIENT_SECRET'
require_text "$CONTRACT_DOC" 'TENANT_ID'
require_text "$CONTRACT_DOC" 'JWT_KEY'
require_text "$CONTRACT_DOC" 'FRPS_BIND_PORT'
require_text "$CONTRACT_DOC" 'FRPS_HTTP_PORT'
require_text "$CONTRACT_DOC" 'FRPS_DASHBOARD_PORT'
require_text "$CONTRACT_DOC" 'FRPS_TCPMUX_PORT'
require_text "$CONTRACT_DOC" 'check_domain'

echo "runtime contract validation passed"
