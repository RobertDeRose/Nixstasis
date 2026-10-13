#!/bin/sh

set -eu

# Render the Compose frps.toml template into a config file frps can load.
#
# usage: frps-render-config.sh TEMPLATE OUTPUT
#
# The Compose frps service runs this with the operator's environment before
# starting frps; the CI config check runs it with dummy values before calling
# `frps verify`. Keeping one renderer means both paths fill the same set of
# placeholders, and any placeholder this script does not know about is an
# error here rather than a literal string that reaches production.

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <template> <output>" >&2
  exit 64
fi

template="$1"
output="$2"

: "${FRPS_DASHBOARD_USER:?FRPS_DASHBOARD_USER is required}"
: "${FRPS_DASHBOARD_PASSWORD:?FRPS_DASHBOARD_PASSWORD is required}"
: "${BASE_DOMAIN:?BASE_DOMAIN is required}"

for port_name in FRPS_BIND_PORT FRPS_DASHBOARD_PORT FRPS_TCPMUX_PORT FRPS_HTTP_PORT; do
  eval "port_value=\${$port_name:-}"
  case "$port_value" in
    '' | *[!0-9]*)
      echo "$port_name must be numeric" >&2
      exit 1
      ;;
  esac
done

escape() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

escaped_frps_dashboard_user=$(escape "$FRPS_DASHBOARD_USER")
escaped_frps_dashboard_password=$(escape "$FRPS_DASHBOARD_PASSWORD")
escaped_base_domain=$(escape "$BASE_DOMAIN")

sed \
  -e "s/\"__FRPS_BIND_PORT__\"/${FRPS_BIND_PORT}/g" \
  -e "s/\"__FRPS_DASHBOARD_PORT__\"/${FRPS_DASHBOARD_PORT}/g" \
  -e "s/__FRPS_DASHBOARD_USER__/${escaped_frps_dashboard_user}/g" \
  -e "s/__FRPS_DASHBOARD_PASSWORD__/${escaped_frps_dashboard_password}/g" \
  -e "s/\"__FRPS_TCPMUX_PORT__\"/${FRPS_TCPMUX_PORT}/g" \
  -e "s/\"__FRPS_HTTP_PORT__\"/${FRPS_HTTP_PORT}/g" \
  -e "s/__BASE_DOMAIN__/${escaped_base_domain}/g" \
  "$template" > "$output"

if grep -nE '__[A-Z_]+__' "$output" >&2; then
  echo "$template has placeholders this renderer does not fill" >&2
  exit 1
fi
