#!/bin/sh

set -eu

# Render the Compose frps.toml template with the renderer shipped in IMAGE,
# using dummy values for every variable the Compose frps service provides,
# then let the frps binary in the same image parse the result.

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TEMPLATE="$ROOT_DIR/deploy/compose/frps/frps.toml"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <frps-image>" >&2
  exit 64
fi

docker run --rm --pull never \
  -v "$TEMPLATE:/etc/frp/frps.toml.template:ro" \
  -e FRPS_DASHBOARD_USER=ci \
  -e FRPS_DASHBOARD_PASSWORD=ci \
  -e BASE_DOMAIN=ci.example \
  -e FRPS_BIND_PORT=7000 \
  -e FRPS_DASHBOARD_PORT=7500 \
  -e FRPS_TCPMUX_PORT=2022 \
  -e FRPS_HTTP_PORT=8080 \
  "$1" /bin/sh -c '
    frps-render-config.sh /etc/frp/frps.toml.template /tmp/frps.toml &&
      frps verify -c /tmp/frps.toml
  '
