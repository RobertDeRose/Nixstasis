#!/bin/sh
#MISE description="Manage the local Compose dev/test deployment"
#USAGE arg "[compose_args]" var=#true help="Compose command/args, or 'up' with dev-lab flags" double_dash="optional"
#USAGE flag "--clients <count>" help="For 'up': number of real Go client containers to start" default="1"

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
ENV_FILE="$COMPOSE_DIR/dev.env"
PROJECT_NAME="nixstasis-dev-lab"

# This task owns its Compose Postgres lifecycle. Prevent local Mix aliases from
# starting the separate dev/test `nixstasis-postgres` Apple Container if a helper
# invoked from here ever shells out to Mix.
export NIXSTASIS_DB_AUTOSTART=false

fail() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: mise run deploy:dev -- up [--clients N]
       mise run deploy:dev -- down
       mise run deploy:dev -- client-logs [--index N] [journalctl-args...]
       mise run deploy:dev -- <compose-cmd> [args...]

Starts a local dev lab with the server, database, caddy, frps, and client
containers. Client simulator containers register as real devices. Down removes
dev-lab containers and volumes, including the local Postgres data volume.

Any unrecognized command is forwarded to docker compose with the correct
project name, compose file, and env file already set.

Examples:
  mise run deploy:dev -- up --clients 2
  mise run deploy:dev -- logs -f nixstasis
  mise run deploy:dev -- logs -f client1
  mise run deploy:dev -- logs -f client
  mise run deploy:dev -- client-logs --index 1 -f
  mise run deploy:dev -- exec nixstasis /bin/bash
EOF
}

compose() {
  docker compose \
    --project-name "$PROJECT_NAME" \
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

wait_for_running_services() {
  expected_services="postgres nixstasis frps caddy"

  if [ "$1" -gt 0 ]; then
    expected_services="$expected_services client"
  fi

  i=0
  while [ "$i" -lt 30 ]; do
    missing_services=""

    for service in $expected_services; do
      if ! compose ps --status running --services "$service" | grep -qx "$service"; then
        missing_services="$missing_services $service"
      fi
    done

    if [ -z "$missing_services" ]; then
      return
    fi

    sleep 1
    i=$((i + 1))
  done

  compose ps >&2 || true

  for service in $expected_services; do
    compose logs --tail=80 "$service" >&2 || true
  done

  fail "dev lab services did not stay running:$missing_services"
}

warn_if_local_mix_postgres_running() {
  command -v container >/dev/null 2>&1 || return

  if container list --all --format json 2>/dev/null |
    grep -q '"id"[[:space:]]*:[[:space:]]*"nixstasis-postgres".*"status"[[:space:]]*:[[:space:]]*"running"'; then
    cat >&2 <<'EOF'
warning: Apple Container nixstasis-postgres is running.
deploy:dev does not use it; Compose uses nixstasis-dev-lab-postgres-1.
Stop it separately if local Mix dev/test tasks do not need it.
EOF
  fi
}

run_migrations() {
  compose up -d --no-deps nixstasis
  compose exec -T nixstasis /app/bin/migrate
}

seed_client_devices() {
  count="$1"
  [ "$count" -gt 0 ] || return

  client_macs=""
  actual=0
  for container_id in $(compose ps -q client); do
    mac_address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' "$container_id")
    [ -n "$mac_address" ] || fail "failed to inspect client container MAC address: $container_id"
    client_macs="$client_macs $mac_address"
    actual=$((actual + 1))
  done

  [ -n "$client_macs" ] || fail "no client containers found to approve"
  [ "$actual" -eq "$count" ] || fail "expected $count client container(s), found $actual"

  elixir_macs="["
  separator=""
  for mac_address in $client_macs; do
    case "$mac_address" in
      [[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]) ;;
      *) fail "unexpected client MAC address: $mac_address" ;;
    esac

    elixir_macs="$elixir_macs$separator\"$mac_address\""
    separator=", "
  done
  elixir_macs="$elixir_macs]"

  rpc_code=$(cat <<ELIXIR_EOF
client_macs = $elixir_macs

client_macs
|> Enum.with_index(1)
|> Enum.each(fn {mac_address, index} ->
  normalized_mac = Nixstasis.Utilities.format_mac_address(mac_address)
  suffix = Integer.to_string(index) |> String.pad_leading(2, "0")

  attrs = %{
    mac_address: normalized_mac,
    account_number: "9100000" <> suffix,
    product_name: "Client Simulator " <> suffix,
    approval_status: :approved,
    metadata: %{
      "dev_lab" => true,
      "client_index" => index,
      "client_simulator" => true
    }
  }

  result =
    case Nixstasis.Domain.get_device_by_mac(normalized_mac) do
      {:ok, nil} -> Nixstasis.Devices.create_device(attrs)
      {:ok, device} -> Nixstasis.Devices.update_device(device, attrs)
      {:error, _reason} -> Nixstasis.Devices.create_device(attrs)
    end

  case result do
    {:ok, _device} -> :ok
    {:error, reason} -> raise "failed to approve client simulator #{index}: #{inspect(reason)}"
  end
end)
ELIXIR_EOF
  )

  compose exec -T nixstasis /app/bin/nixstasis rpc "$rpc_code"
}

client_logs() {
  index=1

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --index)
        shift
        index="${1:-}"
        [ -n "$index" ] || fail "--index requires a value"
        shift || true
        break
        ;;
      --index=*)
        index="${1#--index=}"
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  case "$index" in
    ''|*[!0-9]*) fail "--index must be a positive integer" ;;
    0) fail "--index must be greater than zero" ;;
  esac

  compose exec -T --index "$index" client journalctl \
    -u nixstasis-registration.service \
    -u nixstasis-poll.service \
    "$@"
}

up() {
  clients="$1"

  command -v docker >/dev/null 2>&1 || fail "docker is required for dev lab"
  [ -f "$ENV_FILE" ] || fail "missing env file: $ENV_FILE"
  warn_if_local_mix_postgres_running

  compose up -d postgres
  run_migrations
  compose up -d --scale client="$clients"
  wait_for_running_services "$clients"
  wait_for_server
  seed_client_devices "$clients"

  cat <<EOF
dev lab is ready

UI:      http://127.0.0.1:4000
HTTPS:   https://nixstasis.localhost
Clients: $clients client container(s)

Stop it with:
  mise run deploy:dev -- down
EOF
}

down() {
  compose down --volumes --remove-orphans
}

compose_passthrough() {
  command_name="$1"
  shift || true

  case "$command_name" in
    logs)
      compose_logs "$@"
      ;;
    *)
      compose "$command_name" "$@"
      ;;
  esac
}

compose_logs() {
  client_index=""

  for arg in "$@"; do
    case "$arg" in
      client[1-9]*)
        index="${arg#client}"
        case "$index" in
          ''|*[!0-9]*) ;;
          *)
            [ -z "$client_index" ] || fail "only one clientN log shorthand can be used at a time"
            client_index="$index"
            ;;
        esac
        ;;
    esac
  done

  [ -n "$client_index" ] || {
    compose logs "$@"
    return
  }

  for arg in "$@"; do
    case "$arg" in
      client[1-9]*)
        index="${arg#client}"
        case "$index" in
          ''|*[!0-9]*) set -- "$@" "$arg" ;;
        esac
        ;;
      *)
        set -- "$@" "$arg"
        ;;
    esac
    shift
  done

  compose logs --index "$client_index" "$@" client
}

parse_dev_lab_args() {
  clients="${usage_clients:-1}"
  command_name=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --clients)
        shift
        clients="${1:-}"
        [ -n "$clients" ] || fail "--clients requires a value"
        ;;
      --clients=*)
        clients="${1#--clients=}"
        ;;
      up)
        command_name="up"
        ;;
      *)
        fail "dev-lab flags only apply to the up command"
        ;;
    esac

    shift || true
  done

  [ "$command_name" = "up" ] || fail "dev-lab flags require the up command"
}

validate_dev_lab_counts() {
  case "$clients" in
    ''|*[!0-9]*) fail "--clients must be a non-negative integer" ;;
  esac
}

command_name="${1:-}"
shift || true

case "$command_name" in
  up)
    clients="${usage_clients:-1}"
    parse_dev_lab_args up "$@"
    validate_dev_lab_counts
    up "$clients"
    ;;
  --clients|--clients=*)
    parse_dev_lab_args "$command_name" "$@"
    validate_dev_lab_counts
    up "$clients"
    ;;
  client-logs)
    client_logs "$@"
    ;;
  down)
    down "$@"
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    compose_passthrough "$command_name" "$@"
    ;;
esac
