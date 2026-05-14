#!/bin/sh

set -eu

if [ "$#" -eq 0 ]; then
  echo "frps requires an explicit command, for example: frps -c /etc/frp/frps.toml" >&2
  exit 64
fi

exec "$@"
