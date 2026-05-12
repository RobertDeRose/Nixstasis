#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
ENV_FILE="$COMPOSE_DIR/dev.env"

fail() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: deploy/compose/scripts/dev-lab.sh up [--devices N] [--clients N]
       deploy/compose/scripts/dev-lab.sh down
       deploy/compose/scripts/dev-lab.sh <compose-cmd> [args...]

Starts a local dev lab with the server, database, caddy, frps, and client
containers. Seeds virtual devices for UI testing.

Any unrecognized command is forwarded to docker compose with the correct
project name, compose file, and env file already set.

Examples:
  deploy/compose/scripts/dev-lab.sh logs -f nixstasis
  deploy/compose/scripts/dev-lab.sh ps
  deploy/compose/scripts/dev-lab.sh exec nixstasis /bin/bash
EOF
}

compose() {
  docker compose \
    --project-name nixstasis-dev-lab \
    -f "$COMPOSE_FILE" \
    --env-file "$ENV_FILE" \
    "$@"
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
  clients="$2"

  command -v docker >/dev/null 2>&1 || fail "docker is required for dev lab"
  [ -f "$ENV_FILE" ] || fail "missing env file: $ENV_FILE"

  compose up -d --build postgres
  run_migrations
  compose up -d --build --scale client="$clients"
  wait_for_server
  seed_devices "$devices"

  cat <<EOF
dev lab is ready

UI:      http://127.0.0.1:4000
HTTPS:   https://nixstasis.localhost
Devices: $devices virtual approved device(s)
Clients: $clients client container(s)

Stop it with:
  deploy/compose/scripts/dev-lab.sh down
EOF
}

down() {
  compose down
}

command_name="${1:-}"
shift || true

case "$command_name" in
  up)
    devices=3
    clients=1

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
        --clients)
          shift
          clients="${1:-}"
          [ -n "$clients" ] || fail "--clients requires a value"
          ;;
        --clients=*)
          clients="${1#--clients=}"
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

    case "$clients" in
      ''|*[!0-9]*) fail "--clients must be a non-negative integer" ;;
    esac

    up "$devices" "$clients"
    ;;
  down)
    down
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    compose "$command_name" "$@"
    ;;
esac
