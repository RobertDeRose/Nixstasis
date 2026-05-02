#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
ENV_FILE="${1:-$COMPOSE_DIR/.env}"

if command -v docker >/dev/null 2>&1; then
  COMPOSE_VARIANT="docker"
elif command -v container-compose >/dev/null 2>&1; then
  COMPOSE_VARIANT="container-compose"
else
  echo "docker compose or container-compose is required" >&2
  exit 1
fi

compose_build() {
  if [ "$COMPOSE_VARIANT" = "docker" ]; then
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build "$@"
    return
  fi

  RENDERED_COMPOSE_FILE=$(mktemp "$COMPOSE_DIR/.nixstasis-compose.XXXXXX.yml")
  trap 'rm -f "$RENDERED_COMPOSE_FILE"' EXIT HUP INT TERM
  "$COMPOSE_DIR/scripts/render_compose.sh" "$ENV_FILE" "$RENDERED_COMPOSE_FILE"
  container-compose build -f "$RENDERED_COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

if [ ! -f "$ENV_FILE" ]; then
  echo "missing env file: $ENV_FILE" >&2
  exit 1
fi

compose_build >/dev/null

for service in caddy nixstasis frps postgres; do
  grep -Eq "^[[:space:]]{2}${service}:$" "$COMPOSE_FILE"
done

echo "compose stack validation passed"
