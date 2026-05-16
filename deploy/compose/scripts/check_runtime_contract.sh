#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
ENV_EXAMPLE="$COMPOSE_DIR/.env.example"
CADDYFILE="$COMPOSE_DIR/caddy/Caddyfile"
FRPS_TOML="$COMPOSE_DIR/frps/frps.toml"
COMPOSE_README="$COMPOSE_DIR/README.md"
DEV_LAB_SCRIPT="$COMPOSE_DIR/scripts/dev-lab.sh"
SERVER_RUNTIME="$ROOT_DIR/packages/server/config/runtime.exs"
SERVER_README="$ROOT_DIR/packages/server/README.md"
SERVER_ENTRYPOINT="$ROOT_DIR/packages/server/bin/server"
SERVER_MIGRATE="$ROOT_DIR/packages/server/bin/migrate"
SERVER_DB_WAIT="$ROOT_DIR/packages/server/bin/wait-for-postgres"
CLIENT_README="$ROOT_DIR/packages/client/README.md"
CLIENT_CONFIG_TEMPLATE="$ROOT_DIR/packages/client/build/root-dir/usr/share/nixstasis/config.example.yaml"
CLIENT_FRPC_TEMPLATE="$ROOT_DIR/packages/client/build/root-dir/usr/share/nixstasis/frpc.toml"
CONTRACT_DOC="$ROOT_DIR/specs/013-nixstasis-packaging-migration/contracts/compose-runtime-contract.md"

fail() {
  echo "$1" >&2
  exit 1
}

require_text() {
  file="$1"
  pattern="$2"

  grep -Eq -- "$pattern" "$file" || fail "missing contract text in $file: $pattern"
}

reject_text() {
  file="$1"
  pattern="$2"

  if grep -Eq -- "$pattern" "$file"; then
    fail "forbidden contract text in $file: $pattern"
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

require_compose_service_env() {
  service="$1"
  env_name="$2"

  awk -v service="$service" -v env_name="$env_name" '
    $0 ~ "^  " service ":$" { in_service = 1; next }
    in_service && /^  [[:alnum:]_-]+:$/ { in_service = 0 }
    in_service && $0 ~ "^[[:space:]]+" env_name ": \\$\\{" env_name "\\}" { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$ROOT_DIR/deploy/compose/docker-compose.yml" ||
    fail "missing $env_name environment wiring for compose service $service"
}

for file in \
  "$ENV_EXAMPLE" \
  "$CADDYFILE" \
  "$FRPS_TOML" \
  "$COMPOSE_README" \
  "$DEV_LAB_SCRIPT" \
  "$SERVER_RUNTIME" \
  "$SERVER_README" \
  "$SERVER_ENTRYPOINT" \
  "$SERVER_MIGRATE" \
  "$SERVER_DB_WAIT" \
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
require_text "$ENV_EXAMPLE" '^AUTHORIZED_ROLES='
require_text "$ENV_EXAMPLE" '^AUTHORIZED_GROUPS='
require_text "$ENV_EXAMPLE" '^FRPS_BIND_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_AUTH_TOKEN='
require_text "$ENV_EXAMPLE" '^FRPS_HTTP_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_DASHBOARD_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_TCPMUX_PORT='
require_text "$ENV_EXAMPLE" '^NIXSTASIS_SERVER_IMAGE_REF=.+@sha256:'
require_text "$ENV_EXAMPLE" '^NIXSTASIS_CADDY_IMAGE_REF=.+@sha256:'
require_text "$ENV_EXAMPLE" '^NIXSTASIS_FRPS_IMAGE_REF=.+@sha256:'
require_text "$CADDYFILE" 'check_domain'
require_text "$CADDYFILE" 'ask http://nixstasis:\{\$PORT\}/api/v1/check_domain'
require_text "$CADDYFILE" 'auth\.\{\$BASE_DOMAIN\}'
require_text "$CADDYFILE" 'nixstasis\.\{\$BASE_DOMAIN\}'
require_text "$CADDYFILE" 'reverse_proxy nixstasis:\{\$PORT\}'
require_text "$CADDYFILE" 'frp-admin\.\{\$BASE_DOMAIN\}'
require_text "$CADDYFILE" 'allow roles \{\$AUTHORIZED_ROLES\}'
require_text "$CADDYFILE" 'allow groups \{\$AUTHORIZED_GROUPS\}'
reject_text "$CADDYFILE" 'ask http://nixstasis:4000/api/v1/check_domain'
reject_text "$CADDYFILE" 'reverse_proxy nixstasis:4000'
reject_text "$CADDYFILE" 'allow roles \*'
reject_text "$CADDYFILE" 'allow groups \*'
require_wildcard_authorize_before_proxy
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
require_text "$SERVER_RUNTIME" 'PORT must be 4000 for supported Compose deployment'
require_compose_service_env nixstasis FRPS_AUTH_TOKEN
require_compose_service_env frps FRPS_AUTH_TOKEN

require_text "$COMPOSE_README" 'DATABASE_URL'
require_text "$COMPOSE_README" 'BASE_DOMAIN'
require_text "$COMPOSE_README" 'AUTHORIZED_ROLES'
require_text "$COMPOSE_README" 'AUTHORIZED_GROUPS'
require_text "$COMPOSE_README" 'check_domain'
require_text "$COMPOSE_README" 'bundled PostgreSQL'
require_text "$COMPOSE_README" 'external PostgreSQL'
require_text "$COMPOSE_README" 'dev-lab\.sh up --devices 3'
require_text "$COMPOSE_README" 'ghcr.io/<owner>/nixstasis-server@sha256:<digest>'
require_text "$COMPOSE_README" 'wait for the `DATABASE_URL` host and'

require_text "$DEV_LAB_SCRIPT" 'up \[--devices N\]'
require_text "$DEV_LAB_SCRIPT" '--devices'
require_text "$DEV_LAB_SCRIPT" 'seed_devices'
require_text "$DEV_LAB_SCRIPT" '/app/bin/nixstasis rpc'
require_text "$DEV_LAB_SCRIPT" 'list_devices\(search: mac_address\)'
require_text "$DEV_LAB_SCRIPT" 'update_device\(device, attrs\)'
require_text "$DEV_LAB_SCRIPT" 'Virtual Device'
require_text "$DEV_LAB_SCRIPT" '9000000'
require_text "$DEV_LAB_SCRIPT" 'approval_status: :approved'
require_text "$DEV_LAB_SCRIPT" 'failed to seed virtual device'

require_text "$SERVER_ENTRYPOINT" 'wait-for-postgres'
require_text "$SERVER_MIGRATE" 'wait-for-postgres'
require_text "$SERVER_DB_WAIT" 'ncat -z'

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
require_text "$SERVER_README" 'FRPS_AUTH_TOKEN'
require_text "$SERVER_README" 'FRPS_HTTP_PORT'
require_text "$SERVER_README" 'FRPS_DASHBOARD_PORT'
require_text "$SERVER_README" 'FRPS_TCPMUX_PORT'

require_text "$CLIENT_README" 'https://nixstasis\.example\.com'
require_text "$CLIENT_README" '/etc/nixstasis/config\.yaml'
require_text "$CLIENT_CONFIG_TEMPLATE" 'https://nixstasis\.example\.com'
require_text "$CLIENT_FRPC_TEMPLATE" 'serverAddr = "\{\{ \.Envs\.FRPS_SERVER_ADDR \}\}"'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPS_SERVER_PORT \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPS_AUTH_TOKEN \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.NAME \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.SSH_NAME \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_WEB_SERVER_ADDR \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_WEB_SERVER_PORT \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_HTTP_LOCAL_ADDR \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_SSH_LOCAL_PORT \}\}'
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
require_text "$CONTRACT_DOC" 'FRPS_AUTH_TOKEN.*`frps`, `nixstasis`'
require_text "$CONTRACT_DOC" 'FRPS_HTTP_PORT'
require_text "$CONTRACT_DOC" 'FRPS_DASHBOARD_PORT'
require_text "$CONTRACT_DOC" 'FRPS_TCPMUX_PORT'
require_text "$CONTRACT_DOC" 'check_domain'

echo "runtime contract validation passed"
