#!/bin/sh

set -eu

# Fill every frps.toml template placeholder with a dummy value, then let the
# frps binary in IMAGE parse the result the same way Compose starts it.

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TEMPLATE="$ROOT_DIR/deploy/compose/frps/frps.toml"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <frps-image>" >&2
  exit 64
fi

docker run --rm -i "$1" /bin/sh -c '
  sed -E \
    -e "s/\"__[A-Z_]+_PORT__\"/7000/g" \
    -e "s/__[A-Z_]+__/ci/g" > /tmp/frps.toml &&
  frps verify -c /tmp/frps.toml
' < "$TEMPLATE"
