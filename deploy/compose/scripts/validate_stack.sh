#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
ENV_FILE="${1:-$COMPOSE_DIR/.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "missing env file: $ENV_FILE" >&2
  exit 1
fi

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config >/dev/null

for service in caddy nixstasis frps postgres; do
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --services | grep -qx "$service"
done

echo "compose stack validation passed"
