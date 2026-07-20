#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
ENV_EXAMPLE="$COMPOSE_DIR/.env.example"
CADDYFILE="$COMPOSE_DIR/caddy/Caddyfile"
DEV_CADDYFILE="$COMPOSE_DIR/caddy/Caddyfile.dev"
FRPS_TOML="$COMPOSE_DIR/frps/frps.toml"
LAPTOP_CADDYFILE="$COMPOSE_DIR/caddy/Caddyfile.laptop"
COMPOSE_README="$COMPOSE_DIR/README.md"
DEV_LAB_SCRIPT="$ROOT_DIR/.mise/tasks/deploy/dev.sh"
SERVER_RUNTIME="$ROOT_DIR/packages/server/config/runtime.exs"
SERVER_DOCKERFILE="$ROOT_DIR/packages/server/Dockerfile"
SERVER_README="$ROOT_DIR/packages/server/README.md"
SERVER_ENTRYPOINT="$ROOT_DIR/packages/server/bin/server"
SERVER_MIGRATE="$ROOT_DIR/packages/server/bin/migrate"
SERVER_DB_WAIT="$ROOT_DIR/packages/server/bin/wait-for-postgres"
CLIENT_README="$ROOT_DIR/packages/client/README.md"
CLIENT_DOCKERFILE="$ROOT_DIR/packages/client/Dockerfile"
CLIENT_POSTINSTALL="$ROOT_DIR/packages/client/build/debian/postinstall.sh"
CLIENT_PMCD_UNIT="$ROOT_DIR/packages/client/build/root-dir/lib/systemd/system/nixstasis-pmcd.service"
CLIENT_PMLOGGER_UNIT="$ROOT_DIR/packages/client/build/root-dir/lib/systemd/system/nixstasis-pmlogger.service"
CLIENT_CONFIG_TEMPLATE="$ROOT_DIR/packages/client/build/root-dir/usr/share/nixstasis/config.example.yaml"
CLIENT_FRPC_TEMPLATE="$ROOT_DIR/packages/client/build/root-dir/usr/share/nixstasis/frpc.toml"
CLIENT_CONTAINER_ENTRYPOINT="$ROOT_DIR/packages/client/build/container-entrypoint.sh"
CONTRACT_DOC="$ROOT_DIR/docs/src/modules/deployment-compose.md"

fail() {
  echo "$1" >&2
  exit 1
}

require_text() {
  file="$1"
  pattern="$2"

  grep -Eq -- "$pattern" "$file" || fail "missing contract text in $file: $pattern"
}

require_literal() {
  file="$1"
  text="$2"

  grep -Fq -- "$text" "$file" || fail "missing contract text in $file: $text"
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
    in_service && $0 ~ "^[[:space:]]+" env_name ": \\$\\{" env_name "(:-[^}]*)?\\}" { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$ROOT_DIR/deploy/compose/docker-compose.yml" ||
    fail "missing $env_name environment wiring for compose service $service"
}

for file in \
  "$ENV_EXAMPLE" \
  "$CADDYFILE" \
  "$DEV_CADDYFILE" \
  "$FRPS_TOML" \
  "$COMPOSE_README" \
  "$DEV_LAB_SCRIPT" \
  "$SERVER_RUNTIME" \
  "$SERVER_README" \
  "$SERVER_ENTRYPOINT" \
  "$SERVER_MIGRATE" \
  "$SERVER_DB_WAIT" \
  "$CLIENT_README" \
  "$CLIENT_DOCKERFILE" \
  "$CLIENT_POSTINSTALL" \
  "$CLIENT_PMCD_UNIT" \
  "$CLIENT_PMLOGGER_UNIT" \
  "$CLIENT_CONFIG_TEMPLATE" \
  "$CLIENT_FRPC_TEMPLATE" \
  "$CLIENT_CONTAINER_ENTRYPOINT" \
  "$CONTRACT_DOC"; do
  [ -f "$file" ] || fail "missing required file: $file"
done

require_text "$ENV_EXAMPLE" '^DATABASE_URL='
require_text "$ENV_EXAMPLE" '^SECRET_KEY_BASE='
require_text "$ENV_EXAMPLE" '^PHX_HOST='
require_text "$ENV_EXAMPLE" '^PORT=4000$'
require_text "$ENV_EXAMPLE" '^NIXSTASIS_SESSION_COOKIE_SECURE=true$'
require_text "$ENV_EXAMPLE" '^PHOENIX_BIND_HOST=127\.0\.0\.1$'
require_text "$ENV_EXAMPLE" '^BASE_DOMAIN='
require_text "$ENV_EXAMPLE" '^CLIENT_ID='
require_text "$ENV_EXAMPLE" '^CLIENT_SECRET='
require_text "$ENV_EXAMPLE" '^TENANT_ID='
require_text "$ENV_EXAMPLE" '^JWT_KEY='
require_text "$ENV_EXAMPLE" '^AUTHORIZED_ROLES='
require_text "$ENV_EXAMPLE" '^AUTHORIZED_GROUPS='
require_text "$ENV_EXAMPLE" '^NIXSTASIS_VIEWER_GROUPS='
require_text "$ENV_EXAMPLE" '^NIXSTASIS_OPERATOR_GROUPS='
require_text "$ENV_EXAMPLE" '^NIXSTASIS_ADMIN_GROUPS='
require_text "$ENV_EXAMPLE" '^FRPS_BIND_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_AUTH_TOKEN='
require_text "$ENV_EXAMPLE" '^FRPS_HTTP_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_DASHBOARD_PORT='
require_text "$ENV_EXAMPLE" '^FRPS_TCPMUX_PORT='
require_text "$ENV_EXAMPLE" '^NIXSTASIS_SSH_FRP_HOST='
require_text "$ENV_EXAMPLE" '^NIXSTASIS_FRP_HTTP_LOCAL_ADDR=127\.0\.0\.1:443$'
require_text "$ENV_EXAMPLE" '^NIXSTASIS_SIMULATOR_HTTP_ENABLED=false$'
require_text "$ENV_EXAMPLE" '^NIXSTASIS_SERVER_IMAGE_REF=.+@sha256:'
require_text "$ENV_EXAMPLE" '^NIXSTASIS_CADDY_IMAGE_REF=.+@sha256:'
require_text "$ENV_EXAMPLE" '^NIXSTASIS_FRPS_IMAGE_REF=.+@sha256:'
require_text "$CADDYFILE" 'check_domain'
require_text "$CADDYFILE" 'ask http://nixstasis:\{\$PORT\}/api/v1/check_domain'
require_text "$CADDYFILE" 'auth\.\{\$BASE_DOMAIN\}'
require_text "$CADDYFILE" 'nixstasis\.\{\$BASE_DOMAIN\}'
require_text "$CADDYFILE" 'reverse_proxy nixstasis:\{\$PORT\}'
require_text "$CADDYFILE" 'path /api/v1/devices/register'
require_text "$CADDYFILE" 'path_regexp \^/api/v1/devices/\[\^/\]\+/heartbeat\$'
require_text "$CADDYFILE" 'path_regexp \^/api/v1/devices/\[\^/\]\+/command_results\$'
require_text "$CADDYFILE" 'path_regexp \^/api/v1/devices/\[\^/\]\+/command_payloads/\[\^/\]\+\$'
require_text "$CADDYFILE" 'handle \{'
require_text "$CADDYFILE" 'frp-admin\.\{\$BASE_DOMAIN\}'
require_text "$CADDYFILE" 'allow roles \{\$AUTHORIZED_ROLES\}'
require_text "$CADDYFILE" 'allow groups \{\$AUTHORIZED_GROUPS\}'
require_text "$CADDYFILE" 'match groups \{\$NIXSTASIS_VIEWER_GROUPS\}'
require_text "$CADDYFILE" 'action add role nixstasis/viewer'
require_text "$CADDYFILE" 'match groups \{\$NIXSTASIS_OPERATOR_GROUPS\}'
require_text "$CADDYFILE" 'action add role nixstasis/operator'
require_text "$CADDYFILE" 'match groups \{\$NIXSTASIS_ADMIN_GROUPS\}'
require_text "$CADDYFILE" 'action add role nixstasis/admin'
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
require_text "$SERVER_RUNTIME" 'optional_env\("NIXSTASIS_SSH_FRP_HOST", "frps"\)'
require_text "$SERVER_RUNTIME" 'FRPS_TCPMUX_PORT'
require_text "$SERVER_RUNTIME" ':ssh_client'
require_text "$SERVER_RUNTIME" 'Deployment\.port\(\)'
require_text "$SERVER_RUNTIME" 'PORT must be 4000 for supported Compose deployment'
require_text "$SERVER_RUNTIME" 'NIXSTASIS_LOCAL_BROWSER_AUTH_FALLBACK'
require_text "$ROOT_DIR/packages/server/config/prod.exs" 'NIXSTASIS_SESSION_COOKIE_SECURE'
require_text "$ROOT_DIR/packages/server/Dockerfile" 'ARG NIXSTASIS_SESSION_COOKIE_SECURE=true'
require_compose_service_env nixstasis FRPS_AUTH_TOKEN
require_compose_service_env nixstasis FRPS_TCPMUX_PORT
require_compose_service_env nixstasis NIXSTASIS_SSH_FRP_HOST
require_compose_service_env frps FRPS_AUTH_TOKEN
require_compose_service_env caddy NIXSTASIS_VIEWER_GROUPS
require_compose_service_env caddy NIXSTASIS_OPERATOR_GROUPS
require_compose_service_env caddy NIXSTASIS_ADMIN_GROUPS

require_text "$COMPOSE_README" 'DATABASE_URL'
require_text "$COMPOSE_README" 'BASE_DOMAIN'
require_text "$COMPOSE_README" 'PHOENIX_BIND_HOST'
require_text "$COMPOSE_README" 'AUTHORIZED_ROLES'
require_text "$COMPOSE_README" 'AUTHORIZED_GROUPS'
require_text "$COMPOSE_README" 'NIXSTASIS_VIEWER_GROUPS'
require_text "$COMPOSE_README" 'NIXSTASIS_OPERATOR_GROUPS'
require_text "$COMPOSE_README" 'NIXSTASIS_ADMIN_GROUPS'
require_text "$COMPOSE_README" 'NIXSTASIS_SESSION_COOKIE_SECURE'
require_text "$COMPOSE_README" 'NIXSTASIS_SIMULATOR_HTTP_ENABLED'
require_text "$COMPOSE_README" 'NIXSTASIS_SSH_FRP_HOST'
require_text "$COMPOSE_README" 'check_domain'
require_text "$COMPOSE_README" 'bundled PostgreSQL'
require_text "$COMPOSE_README" 'external PostgreSQL'
require_text "$COMPOSE_README" 'mise run deploy:dev -- up --clients 3'
require_text "$COMPOSE_README" 'Caddyfile\.dev'
require_text "$COMPOSE_README" 'client-logs'
require_text "$COMPOSE_README" 'journald'
require_text "$COMPOSE_README" 'Performance Co-Pilot'
require_text "$COMPOSE_README" 'PostgreSQL data volume'
require_text "$COMPOSE_README" 'no longer seeds database-only virtual devices'
require_text "$COMPOSE_README" 'client1'
require_text "$COMPOSE_README" 'ghcr.io/<owner>/nixstasis-server@sha256:<digest>'
require_text "$COMPOSE_README" 'wait for the `DATABASE_URL` host and'

require_text "$DEV_CADDYFILE" 'reverse_proxy nixstasis:\{\$PORT\}'
require_text "$DEV_CADDYFILE" 'reverse_proxy frps:\{\$FRPS_HTTP_PORT\}'
require_text "$DEV_CADDYFILE" 'tls internal'
reject_text "$DEV_CADDYFILE" 'security \{'
reject_text "$DEV_CADDYFILE" 'authorize with entra_policy'
reject_text "$DEV_CADDYFILE" 'on_demand'

require_text "$DEV_LAB_SCRIPT" '#USAGE flag "--clients <count>"'
require_text "$DEV_LAB_SCRIPT" 'NIXSTASIS_DB_AUTOSTART=false'
require_text "$DEV_LAB_SCRIPT" 'Apple Container nixstasis-postgres is running'
require_text "$DEV_LAB_SCRIPT" 'down "\$@"'
reject_text "$DEV_LAB_SCRIPT" '--devices'
reject_text "$DEV_LAB_SCRIPT" 'seed_devices'
require_text "$DEV_LAB_SCRIPT" '/app/bin/nixstasis rpc'
require_text "$DEV_LAB_SCRIPT" 'get_device_by_mac\(normalized_mac\)'
require_text "$DEV_LAB_SCRIPT" 'update_device\(device, attrs\)'
reject_text "$DEV_LAB_SCRIPT" 'Virtual Device'
require_text "$DEV_LAB_SCRIPT" 'seed_client_devices'
require_text "$DEV_LAB_SCRIPT" 'client-logs'
require_text "$DEV_LAB_SCRIPT" 'journalctl'
require_text "$DEV_LAB_SCRIPT" 'compose down --volumes --remove-orphans'
reject_text "$DEV_LAB_SCRIPT" '9000000'
require_text "$DEV_LAB_SCRIPT" '9100000'
require_text "$DEV_LAB_SCRIPT" 'approval_status: :approved'
reject_text "$DEV_LAB_SCRIPT" 'failed to seed virtual device'
require_text "$DEV_LAB_SCRIPT" 'failed to approve client simulator'

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
require_text "$SERVER_README" 'NIXSTASIS_SSH_FRP_HOST'
require_text "$SERVER_README" 'NIXSTASIS_SESSION_COOKIE_SECURE=false'

require_text "$CLIENT_README" 'https://nixstasis\.example\.com'
require_text "$CLIENT_README" '/etc/nixstasis/config\.yaml'
require_text "$CLIENT_README" 'container image entrypoint writes'
require_text "$CLIENT_README" 'login shell'
require_text "$CLIENT_CONFIG_TEMPLATE" 'https://nixstasis\.example\.com'
require_text "$CLIENT_CONTAINER_ENTRYPOINT" 'NIXSTASIS_API_URL'
require_text "$CLIENT_CONTAINER_ENTRYPOINT" 'NIXSTASIS_FRP_SERVER_ADDR'
require_text "$CLIENT_CONTAINER_ENTRYPOINT" 'NIXSTASIS_SIMULATOR_HTTP_ENABLED'
require_text "$CLIENT_CONTAINER_ENTRYPOINT" 'start_pcp_without_systemd'
require_text "$CLIENT_CONTAINER_ENTRYPOINT" '/var/lib/pcp/pmns/Rebuild'
require_text "$CLIENT_CONTAINER_ENTRYPOINT" '/usr/lib/pcp/bin/pmcd -A'
require_text "$CLIENT_CONTAINER_ENTRYPOINT" 'pmlogger -L -P'
require_text "$CLIENT_CONTAINER_ENTRYPOINT" 'pcp-metrics'
require_literal "$DEV_LAB_SCRIPT" '[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]])'
require_text "$LAPTOP_CADDYFILE" 'Content-Security-Policy.*frame-ancestors .self. https://nixstasis\.\{\$BASE_DOMAIN\}'
require_text "$ROOT_DIR/deploy/compose/docker-compose.yml" 'NIXSTASIS_FRP_HTTP_LOCAL_ADDR'
require_text "$ROOT_DIR/deploy/compose/docker-compose.yml" 'NIXSTASIS_SIMULATOR_HTTP_ENABLED'
require_text "$CLIENT_DOCKERFILE" 'container-entrypoint'
require_text "$CLIENT_DOCKERFILE" 'pcp-metrics\.sh'
require_text "$SERVER_DOCKERFILE" 'COPY client/scripts/e2e/journeys priv/e2e/journeys'
require_text "$SERVER_RUNTIME" 'Application\.app_dir\(:nixstasis, "priv"\)'
require_text "$SERVER_RUNTIME" ':e2e_journey_dir'
require_text "$CLIENT_DOCKERFILE" 'openssl'
require_text "$CLIENT_DOCKERFILE" '^      pcp \\'
require_text "$CLIENT_DOCKERFILE" '\./Rebuild'
require_text "$CLIENT_DOCKERFILE" 'systemctl disable pmcd\.service pmlogger\.service pmie\.service pmproxy\.service'
require_text "$CLIENT_DOCKERFILE" 'systemctl enable nixstasis-pmcd\.service'
require_text "$CLIENT_DOCKERFILE" 'systemctl enable nixstasis-pmlogger\.service'
require_text "$CLIENT_PMCD_UNIT" '/var/lib/pcp/pmns.*Rebuild'
require_text "$CLIENT_PMCD_UNIT" '/usr/lib/pcp/bin/pmcd -f -A'
require_text "$CLIENT_PMLOGGER_UNIT" 'pmlogger -L -P'
require_text "$CLIENT_DOCKERFILE" 'sudo'
require_text "$CLIENT_DOCKERFILE" 'systemctl add-wants multi-user\.target systemd-user-sessions\.service'
require_text "$CLIENT_DOCKERFILE" 'useradd --system --create-home --home-dir /var/lib/nixstasis --shell /usr/sbin/nologin nixstasis'
require_text "$CLIENT_DOCKERFILE" 'useradd --system --create-home --home-dir /var/lib/nixstasis-support --shell /bin/bash nixstasis-support'
require_text "$CLIENT_DOCKERFILE" 'nixstasis-support ALL=\(ALL\) NOPASSWD:ALL'
require_text "$CLIENT_POSTINSTALL" 'useradd --system --create-home --home-dir /var/lib/nixstasis --shell /usr/sbin/nologin nixstasis'
require_text "$CLIENT_POSTINSTALL" 'usermod --home /var/lib/nixstasis nixstasis'
require_text "$CLIENT_POSTINSTALL" 'useradd --system --create-home --home-dir /var/lib/nixstasis-support --shell /bin/bash nixstasis-support'
require_text "$CLIENT_POSTINSTALL" 'usermod --home /var/lib/nixstasis-support --shell /bin/bash nixstasis-support'
require_text "$CLIENT_POSTINSTALL" 'chown -R nixstasis:nixstasis /var/lib/nixstasis'
require_text "$CLIENT_POSTINSTALL" 'chown -R nixstasis-support:nixstasis-support /var/lib/nixstasis-support'
require_text "$CLIENT_POSTINSTALL" 'nixstasis-support ALL=\(ALL\) NOPASSWD:ALL'
require_text "$ROOT_DIR/packages/client/build/root-dir/lib/systemd/system/nixstasis-simulator-http.service" 'nixstasis-simulator-http'
require_text "$ROOT_DIR/packages/client/build/root-dir/usr/share/nixstasis/simulator-http.sh" 'openssl s_server'
require_text "$CLIENT_FRPC_TEMPLATE" 'serverAddr = "\{\{ \.Envs\.FRPS_SERVER_ADDR \}\}"'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPS_SERVER_PORT \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPS_AUTH_TOKEN \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.NAME \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.SSH_NAME \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.PCP_NAME \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_WEB_SERVER_ADDR \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_WEB_SERVER_PORT \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_HTTP_LOCAL_ADDR \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_SSH_LOCAL_PORT \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" '\{\{ \.Envs\.FRPC_PCP_LOCAL_PORT \}\}'
require_text "$CLIENT_FRPC_TEMPLATE" 'atom-<normalized-device-id>\.<base-domain>'

require_text "$CONTRACT_DOC" 'DATABASE_URL'
require_text "$CONTRACT_DOC" 'SECRET_KEY_BASE'
require_text "$CONTRACT_DOC" 'PHX_HOST'
require_text "$CONTRACT_DOC" 'PORT'
require_text "$CONTRACT_DOC" 'PHOENIX_BIND_HOST'
require_text "$CONTRACT_DOC" 'NIXSTASIS_SESSION_COOKIE_SECURE'
require_text "$CONTRACT_DOC" 'BASE_DOMAIN'
require_text "$CONTRACT_DOC" 'CLIENT_ID'
require_text "$CONTRACT_DOC" 'CLIENT_SECRET'
require_text "$CONTRACT_DOC" 'TENANT_ID'
require_text "$CONTRACT_DOC" 'JWT_KEY'
require_text "$CONTRACT_DOC" 'NIXSTASIS_VIEWER_GROUPS'
require_text "$CONTRACT_DOC" 'NIXSTASIS_OPERATOR_GROUPS'
require_text "$CONTRACT_DOC" 'NIXSTASIS_ADMIN_GROUPS'
require_text "$CONTRACT_DOC" 'FRPS_BIND_PORT'
require_text "$CONTRACT_DOC" 'FRPS_AUTH_TOKEN.*`frps`, `nixstasis`'
require_text "$CONTRACT_DOC" 'FRPS_HTTP_PORT'
require_text "$CONTRACT_DOC" 'FRPS_DASHBOARD_PORT'
require_text "$CONTRACT_DOC" 'FRPS_TCPMUX_PORT'
require_text "$CONTRACT_DOC" 'NIXSTASIS_SSH_FRP_HOST'
require_text "$CONTRACT_DOC" 'NIXSTASIS_API_URL'
require_text "$CONTRACT_DOC" 'Caddyfile\.dev'
require_text "$CONTRACT_DOC" 'client-logs'
require_text "$CONTRACT_DOC" 'down.*named volumes'
require_text "$CONTRACT_DOC" 'check_domain'

echo "runtime contract validation passed"
