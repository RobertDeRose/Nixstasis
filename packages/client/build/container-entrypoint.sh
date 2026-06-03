#!/bin/sh

set -eu

yaml_string() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

require_numeric() {
  name="$1"
  value="$2"

  case "$value" in
    ''|*[!0-9]*)
      echo "$name must be numeric" >&2
      exit 1
      ;;
  esac
}

enable_simulator_http() {
  case "${NIXSTASIS_SIMULATOR_HTTP_ENABLED:-false}" in
    true|TRUE|1|yes|YES)
      systemctl enable nixstasis-simulator-http.service >/dev/null
      ;;
    false|FALSE|0|no|NO|'')
      ;;
    *)
      echo "NIXSTASIS_SIMULATOR_HTTP_ENABLED must be true or false" >&2
      exit 1
      ;;
  esac
}

start_pcp_without_systemd() {
  if command -v pminfo >/dev/null 2>&1 && pminfo pmcd.version >/dev/null 2>&1; then
    return
  fi

  if [ -x /var/lib/pcp/pmns/Rebuild ] && [ ! -s /var/lib/pcp/pmns/root ]; then
    (cd /var/lib/pcp/pmns && ./Rebuild) >/dev/null 2>&1 || echo "failed to rebuild PCP namespace" >&2
  fi

  if [ -x /usr/lib/pcp/bin/pmcd ]; then
    /usr/lib/pcp/bin/pmcd -A -l /var/log/pcp/pmcd/pmcd.log >/dev/null 2>&1 || echo "failed to start pmcd" >&2
  fi

  if command -v pmlogger >/dev/null 2>&1; then
    pmlogger -L -P -c /etc/pcp/pmlogger/config.pmstat -l /var/log/pcp/pmlogger/pmlogger.log -t 10s /var/log/pcp/pmlogger/nixstasis >/dev/null 2>&1 || echo "failed to start pmlogger" >&2
  fi
}

write_compose_config() {
  if [ -z "${NIXSTASIS_API_URL:-}" ] && [ -z "${NIXSTASIS_FRP_SERVER_ADDR:-}" ] && [ -z "${NIXSTASIS_FRP_SERVER_PORT:-}" ]; then
    return
  fi

  api_url="${NIXSTASIS_API_URL:-http://localhost:4000}"
  poll_interval="${NIXSTASIS_POLL_INTERVAL:-10s}"
  frp_server_addr="${NIXSTASIS_FRP_SERVER_ADDR:-nixstasis.example.com}"
  frp_server_port="${NIXSTASIS_FRP_SERVER_PORT:-7000}"
  frp_web_server_addr="${NIXSTASIS_FRP_WEB_SERVER_ADDR:-127.0.0.1}"
  frp_web_server_port="${NIXSTASIS_FRP_WEB_SERVER_PORT:-7400}"
  frp_http_local_addr="${NIXSTASIS_FRP_HTTP_LOCAL_ADDR:-127.0.0.1:443}"
  frp_ssh_local_port="${NIXSTASIS_FRP_SSH_LOCAL_PORT:-22}"

  require_numeric NIXSTASIS_FRP_SERVER_PORT "$frp_server_port"
  require_numeric NIXSTASIS_FRP_WEB_SERVER_PORT "$frp_web_server_port"
  require_numeric NIXSTASIS_FRP_SSH_LOCAL_PORT "$frp_ssh_local_port"

  config_file="${NIXSTASIS_CONFIG_FILE:-/etc/nixstasis/config.yaml}"
  config_dir="${config_file%/*}"
  if [ "$config_dir" = "$config_file" ]; then
    config_dir="."
  fi

  mkdir -p "$config_dir"
  cat > "$config_file" <<EOF
api:
  url: $(yaml_string "$api_url")

poll:
  interval: $(yaml_string "$poll_interval")

frp:
  server_addr: $(yaml_string "$frp_server_addr")
  server_port: $frp_server_port
  web_server_addr: $(yaml_string "$frp_web_server_addr")
  web_server_port: $frp_web_server_port
  http_local_addr: $(yaml_string "$frp_http_local_addr")
  ssh_local_port: $frp_ssh_local_port

runtime:
  authorized_keys_path: '/var/lib/nixstasis-support/.ssh/authorized_keys'
  exec_work_dir: '/'
  exec_commands:
    pcp-metrics: '/usr/libexec/nixstasis/pcp-metrics.sh'
EOF
}

write_compose_config

if [ "$#" -eq 0 ]; then
  enable_simulator_http
  exec /lib/systemd/systemd
fi

start_pcp_without_systemd
exec "$@"
