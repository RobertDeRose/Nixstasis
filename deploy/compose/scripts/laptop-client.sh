#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
CLIENT_DIR="$ROOT_DIR/packages/client"
ENV_FILE="$COMPOSE_DIR/laptop.env"
STATE_DIR="${NIXSTASIS_LAPTOP_CLIENT_STATE_DIR:-$COMPOSE_DIR/.laptop-client}"
CONFIG_FILE="$STATE_DIR/config.yaml"
FRPC_CONFIG_FILE="$STATE_DIR/frpc.toml"
IDENTITY_FILE="$STATE_DIR/id"
FRPC_BINARY="${NIXSTASIS_FRPC_BINARY_PATH:-}"

fail() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: deploy/compose/scripts/laptop-client.sh <prepare|register|poll|validate-frpc> [client args...]

Environment:
  NIXSTASIS_LAPTOP_CLIENT_STATE_DIR  Defaults to deploy/compose/.laptop-client.
  NIXSTASIS_FRPC_BINARY_PATH         Optional for poll, required for validate-frpc.

Run deploy/compose/scripts/laptop.sh validate before starting the laptop client.
EOF
}

env_value() {
  key="$1"

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
}

require_file() {
  file="$1"
  [ -f "$file" ] || fail "missing required file: $file"
}

require_env_value() {
  name="$1"
  value=$(env_value "$name" || true)

  [ -n "$value" ] || fail "missing required laptop env value: $name"

  case "$value" in
    replace-me*|00000000-0000-0000-0000-000000000000)
      fail "$name must be replaced before laptop client mode is used"
      ;;
  esac
}

prepare() {
  require_file "$ENV_FILE"
  require_env_value FRPS_AUTH_TOKEN

  umask 077
mkdir -p "$STATE_DIR/scripts"
chmod 700 "$STATE_DIR"
touch "$STATE_DIR/authorized_keys"
chmod 600 "$STATE_DIR/authorized_keys"

  cat > "$CONFIG_FILE" <<EOF
api:
  url: "https://nixstasis.localhost"

poll:
  interval: 10s

scripts:
  dir: "$STATE_DIR/scripts"

frp:
  auth_token: "$(env_value FRPS_AUTH_TOKEN)"

runtime:
  authorized_keys_path: "$STATE_DIR/authorized_keys"
  exec_work_dir: "$STATE_DIR"
  exec_env:
    - "LANG=C"

log:
  level: "info"
  format: "text"
EOF
  chmod 600 "$CONFIG_FILE"

  cat > "$FRPC_CONFIG_FILE" <<EOF
serverAddr = "127.0.0.1"
serverPort = $(env_value FRPS_BIND_PORT)
auth.method = "token"
auth.token = "{{ .Envs.FRPS_AUTH_TOKEN }}"
webServer.addr = "127.0.0.1"
webServer.port = 7400
log.to = "console"

[[proxies]]
name = "{{ .Envs.NAME }}"
type = "http"
subdomain = "{{ .Envs.NAME }}"

[proxies.plugin]
type = "http2https"
localAddr = "127.0.0.1:443"

[[proxies]]
name = "{{ .Envs.NAME }}-ssh"
type = "tcpmux"
multiplexer = "httpconnect"
customDomains = ["{{ .Envs.NAME }}-ssh"]
localIP = "127.0.0.1"
localPort = $(env_value LAPTOP_SSH_PORT)
EOF
  chmod 600 "$FRPC_CONFIG_FILE"

  echo "prepared laptop client state in $STATE_DIR"
}

run_client() {
  subcommand="$1"
  shift

  prepare

  if [ -n "$FRPC_BINARY" ]; then
    require_file "$FRPC_BINARY"
  fi

  cd "$CLIENT_DIR"
  NIXSTASIS_IDENTITY_PATH="$IDENTITY_FILE" \
    NIXSTASIS_CONFIG_FILE="$CONFIG_FILE" \
    NIXSTASIS_FRPC_CONFIG_PATH="$FRPC_CONFIG_FILE" \
    NIXSTASIS_FRPC_BINARY_PATH="$FRPC_BINARY" \
    go run ./cmd/nixstasis "$subcommand" "$@"
}

validate_frpc() {
  prepare

  if [ -z "$FRPC_BINARY" ]; then
    fail "NIXSTASIS_FRPC_BINARY_PATH is required for FRPC validation"
  fi

  require_file "$FRPC_BINARY"

  rendered_config=$(mktemp "$STATE_DIR/frpc-rendered.XXXXXX.toml")
  frpc_log=$(mktemp "$STATE_DIR/frpc.XXXXXX.log")
  frpc_pid=""
cleanup_frpc_validation() {
    if [ -n "$frpc_pid" ] && kill -0 "$frpc_pid" >/dev/null 2>&1; then
      kill "$frpc_pid" >/dev/null 2>&1 || true

      i=0
      while kill -0 "$frpc_pid" >/dev/null 2>&1 && [ "$i" -lt 10 ]; do
        sleep 1
        i=$((i + 1))
      done

      if kill -0 "$frpc_pid" >/dev/null 2>&1; then
        kill -KILL "$frpc_pid" >/dev/null 2>&1 || true
      fi

      wait "$frpc_pid" 2>/dev/null || true
    fi

    rm -f "$rendered_config" "$frpc_log"
  }
  trap cleanup_frpc_validation EXIT HUP INT TERM

  name="atom-laptopvalidate"
  FRPS_AUTH_TOKEN="$(env_value FRPS_AUTH_TOKEN)" NAME="$name" perl -0pe '
    sub toml_escape {
      my ($value) = @_;
      $value =~ s/\\/\\\\/g;
      $value =~ s/"/\\"/g;
      return $value;
    }

    s/\{\{ \.Envs\.FRPS_AUTH_TOKEN \}\}/toml_escape($ENV{FRPS_AUTH_TOKEN})/ge;
    s/\{\{ \.Envs\.NAME \}\}/toml_escape($ENV{NAME})/ge;
  ' "$FRPC_CONFIG_FILE" > "$rendered_config"
  chmod 600 "$rendered_config"

  "$FRPC_BINARY" -c "$rendered_config" >"$frpc_log" 2>&1 &
  frpc_pid=$!

  sleep 5

  if ! kill -0 "$frpc_pid" >/dev/null 2>&1; then
    cat "$frpc_log" >&2
    fail "frpc exited before connectivity could be validated"
  fi

  kill "$frpc_pid" >/dev/null 2>&1 || true
  wait "$frpc_pid" 2>/dev/null || true

  if grep -Eiq 'login to server success|start proxy success|proxy added|client login info' "$frpc_log"; then
    trap - EXIT HUP INT TERM
    cleanup_frpc_validation
    echo "laptop FRPC validation passed"
  else
    cat "$frpc_log" >&2
    fail "frpc did not report a successful connection"
  fi
}

command_name="${1:-}"

if [ -z "$command_name" ]; then
  usage
  exit 2
fi

shift

case "$command_name" in
  prepare)
    prepare
    ;;
  register)
    run_client register "$@"
    ;;
  poll)
    run_client poll "$@"
    ;;
  validate-frpc)
    validate_frpc
    ;;
  *)
    usage
    exit 2
    ;;
esac
