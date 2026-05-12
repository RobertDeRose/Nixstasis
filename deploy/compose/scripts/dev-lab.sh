#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
BASE_COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
LAPTOP_COMPOSE_FILE="$COMPOSE_DIR/docker-compose.laptop.yml"
DEV_LAB_COMPOSE_FILE="$COMPOSE_DIR/docker-compose.dev-lab.yml"
ENV_FILE="$COMPOSE_DIR/laptop.env"
STATE_DIR="$COMPOSE_DIR/.laptop-client"

fail() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: deploy/compose/scripts/dev-lab.sh up [--devices N]
       deploy/compose/scripts/dev-lab.sh down

Starts a local server lab and seeds approved virtual devices for UI testing.
EOF
}

compose() {
  docker compose \
    --project-name nixstasis-dev-lab \
    -f "$BASE_COMPOSE_FILE" \
    -f "$LAPTOP_COMPOSE_FILE" \
    -f "$DEV_LAB_COMPOSE_FILE" \
    --profile bundled-db \
    --env-file "$ENV_FILE" \
    "$@"
}

ensure_env() {
  if [ -f "$ENV_FILE" ]; then
    return
  fi

  umask 077
  cat > "$ENV_FILE" <<'EOF'
DATABASE_URL=ecto://postgres:postgres@postgres/nixstasis
SECRET_KEY_BASE=dev-lab-secret-key-base-dev-lab-secret-key-base-dev-lab-secret-key-base
PHX_HOST=nixstasis.localhost
PORT=4000
BASE_DOMAIN=localhost
NIXSTASIS_TLS_OBSERVATIONS_ENABLED=true
NIXSTASIS_TLS_OBSERVATIONS_TOKEN=dev-lab-tls-observations-token
NIXSTASIS_FORCE_SSL=false
ACME_EMAIL=dev-null@nixstasis.localhost
CLIENT_ID=dev-lab-client-id
CLIENT_SECRET=dev-lab-client-secret
TENANT_ID=dev-lab-tenant-id
JWT_KEY=dev-lab-jwt-key
AUTHORIZED_ROLES=nixstasis-operator
AUTHORIZED_GROUPS=dev-lab-operators
FRPS_BIND_PORT=7000
FRPS_AUTH_TOKEN=dev-lab-frps-token
FRPS_HTTP_PORT=8080
FRPS_DASHBOARD_PORT=8081
FRPS_DASHBOARD_USER=admin
FRPS_DASHBOARD_PASSWORD=dev-lab-frps-dashboard-password
FRPS_TCPMUX_PORT=2022
LAPTOP_SSH_PORT=2222
LAPTOP_SSH_IMAGE_REF=lscr.io/linuxserver/openssh-server:version-9.9_p2-r0
POSTGRES_VERSION=17-alpine
POSTGRES_IMAGE_DIGEST=sha256:0000000000000000000000000000000000000000000000000000000000000000
POSTGRES_DB=nixstasis
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
NIXSTASIS_SERVER_IMAGE_REF=nixstasis-server:laptop
NIXSTASIS_CADDY_IMAGE_REF=nixstasis-caddy:laptop
NIXSTASIS_FRPS_IMAGE_REF=nixstasis-frps:laptop
EOF
  echo "created $ENV_FILE with local dev-lab defaults"
}

ensure_client_state() {
  umask 077
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/authorized_keys"
  chmod 700 "$STATE_DIR"
  chmod 600 "$STATE_DIR/authorized_keys"
}

wait_for_server() {
  i=0
  while [ "$i" -lt 60 ]; do
    if curl --silent --show-error --max-time 2 http://127.0.0.1:4000/ >/dev/null 2>&1; then
      return
    fi

    sleep 2
    i=$((i + 1))
  done

  fail "server did not become ready within 120 seconds"
}

run_migrations() {
  compose run --rm nixstasis /app/bin/migrate
}

seed_devices() {
  count="$1"

  rpc_code=$(cat <<ELIXIR_EOF
count = $count

for index <- 1..count do
  suffix = Integer.to_string(index) |> String.pad_leading(2, "0")
  mac_address = "02:00:00:00:00:" <> suffix

  attrs = %{
    mac_address: mac_address,
    account_number: "9000000" <> suffix,
    product_name: "Virtual Device " <> suffix,
    approval_status: :approved,
    last_seen_at: DateTime.utc_now(),
    ipv4_address: "10.88.0.#{index}",
    metadata: %{
      "dev_lab" => true,
      "virtual_index" => index
    }
  }

  result =
    case Nixstasis.Devices.list_devices(search: mac_address) do
      [device | _] -> Nixstasis.Devices.update_device(device, attrs)
      [] -> Nixstasis.Devices.create_device(attrs)
    end

  case result do
    {:ok, _device} -> :ok
    {:error, reason} -> raise "failed to seed virtual device #{index}: #{inspect(reason)}"
  end
end
ELIXIR_EOF
  )

  compose exec -T nixstasis /app/bin/nixstasis rpc "$rpc_code"
}

up() {
  devices="$1"

  command -v docker >/dev/null 2>&1 || fail "docker is required for dev lab"
  ensure_env
  ensure_client_state

  compose up -d --build postgres
  run_migrations
  compose up -d --build
  wait_for_server
  seed_devices "$devices"

  cat <<EOF
dev lab is ready

UI:      http://127.0.0.1:4000
HTTPS:   https://nixstasis.localhost
Devices: $devices virtual approved device(s)

Stop it with:
  deploy/compose/scripts/dev-lab.sh down
EOF
}

down() {
  ensure_env
  compose down
}

command_name="${1:-}"
shift || true

case "$command_name" in
  up)
    devices=3

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --devices)
          shift
          devices="${1:-}"
          [ -n "$devices" ] || fail "--devices requires a value"
          ;;
        --devices=*)
          devices="${1#--devices=}"
          ;;
        *)
          usage
          exit 2
          ;;
      esac
      shift || true
    done

    case "$devices" in
      ''|*[!0-9]*) fail "--devices must be a positive integer" ;;
      0) fail "--devices must be greater than zero" ;;
    esac

    up "$devices"
    ;;
  down)
    down
    ;;
  *)
    usage
    exit 2
    ;;
esac
