#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
BASE_COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
LAPTOP_COMPOSE_FILE="$COMPOSE_DIR/docker-compose.laptop.yml"
ENV_FILE="$COMPOSE_DIR/laptop.env"
LAPTOP_ENV_EXAMPLE="$COMPOSE_DIR/laptop.env.example"
LAPTOP_CADDYFILE="$COMPOSE_DIR/caddy/Caddyfile.laptop"

fail() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: deploy/compose/scripts/laptop.sh <start|stop|validate|validate-tls> [compose args...]

Before first use, copy deploy/compose/laptop.env.example to deploy/compose/laptop.env
and replace placeholder secrets.
EOF
}

https_check() {
  host="$1"

  curl --silent --show-error --insecure --resolve "$host:443:127.0.0.1" \
    --max-time 10 \
    --output /dev/null \
    --write-out '%{http_code}' \
    "https://$host/"
}

api_request() {
  method="$1"
  path="$2"

  tmp_body=$(mktemp)
  status=$(curl --silent --show-error --location \
    --max-time 10 \
    --header "X-Forwarded-Proto: https" \
    --header "X-Nixstasis-TLS-Observations-Token: $(env_value NIXSTASIS_TLS_OBSERVATIONS_TOKEN)" \
    --request "$method" \
    --output "$tmp_body" \
    --write-out '%{http_code}' \
    "http://127.0.0.1:4000$path")

  cat "$tmp_body"
  rm -f "$tmp_body"

  case "$status" in
    200|204)
      ;;
    *)
      fail "diagnostic request $method $path returned HTTP $status"
      ;;
  esac
}

cert_issuer() {
  host="$1"

  echo | openssl s_client -connect 127.0.0.1:443 -servername "$host" 2>/dev/null | \
    openssl x509 -noout -issuer 2>/dev/null
}

cert_sans() {
  host="$1"

  echo | openssl s_client -connect 127.0.0.1:443 -servername "$host" 2>/dev/null | \
    openssl x509 -noout -ext subjectAltName 2>/dev/null
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
  [ "$value" != "*" ] || fail "$name must be least-privilege and cannot be wildcard"

  case "$value" in
    replace-me*)
      fail "$name must be replaced before laptop mode is used"
      ;;
    00000000-0000-0000-0000-000000000000)
      fail "$name must be replaced with a real least-privilege value"
      ;;
  esac
}

require_exact_env_value() {
  name="$1"
  expected="$2"
  value=$(env_value "$name" || true)

  [ -n "$value" ] || fail "missing required laptop env value: $name"
  [ "$value" = "$expected" ] || fail "$name must be $expected for laptop mode, got: $value"
}

require_digest_ref() {
  name="$1"
  value=$(env_value "$name" || true)

  [ -n "$value" ] || fail "missing required laptop env value: $name"

  case "$value" in
    *@sha256:replace-*)
      fail "$name must use a real digest, got placeholder: $value"
      ;;
  esac

  printf '%s\n' "$value" | grep -Eq '@sha256:[0-9a-f]{64}$' || \
    fail "$name must be an immutable digest reference, got: $value"
}

require_text() {
  file="$1"
  pattern="$2"

  grep -Eq "$pattern" "$file" || fail "missing required text in $file: $pattern"
}

reject_text() {
  file="$1"
  pattern="$2"

  if grep -Eq "$pattern" "$file"; then
    fail "forbidden text in $file: $pattern"
  fi
}

compose() {
  docker compose \
    -f "$BASE_COMPOSE_FILE" \
    -f "$LAPTOP_COMPOSE_FILE" \
    --profile bundled-db \
    --env-file "$ENV_FILE" \
    "$@"
}

validate() {
  command -v docker >/dev/null 2>&1 || fail "docker is required for laptop mode"

  require_file "$BASE_COMPOSE_FILE"
  require_file "$LAPTOP_COMPOSE_FILE"
  require_file "$LAPTOP_ENV_EXAMPLE"
  require_file "$LAPTOP_CADDYFILE"
  require_file "$ENV_FILE"

  require_exact_env_value PORT 4000
  require_exact_env_value BASE_DOMAIN localhost
  require_exact_env_value PHX_HOST nixstasis.localhost
  require_env_value SECRET_KEY_BASE
  require_env_value CLIENT_ID
  require_env_value CLIENT_SECRET
  require_env_value TENANT_ID
  require_env_value JWT_KEY
  require_env_value AUTHORIZED_ROLES
  require_env_value AUTHORIZED_GROUPS
  require_env_value FRPS_AUTH_TOKEN
  require_env_value FRPS_DASHBOARD_USER
  require_env_value FRPS_DASHBOARD_PASSWORD
  require_env_value LAPTOP_SSH_PORT
  require_digest_ref LAPTOP_SSH_IMAGE_REF
  require_env_value NIXSTASIS_TLS_OBSERVATIONS_TOKEN
  require_exact_env_value NIXSTASIS_TLS_OBSERVATIONS_ENABLED true
  require_exact_env_value NIXSTASIS_FORCE_SSL false
  require_file "$COMPOSE_DIR/.laptop-client/authorized_keys"

  require_text "$LAPTOP_CADDYFILE" 'ask http://nixstasis:\{\$PORT\}/api/v1/check_domain'
  require_text "$LAPTOP_CADDYFILE" 'issuer internal'
  require_text "$LAPTOP_CADDYFILE" 'auth\.\{\$BASE_DOMAIN\}'
  require_text "$LAPTOP_CADDYFILE" 'nixstasis\.\{\$BASE_DOMAIN\}'
  require_text "$LAPTOP_CADDYFILE" 'frp-admin\.\{\$BASE_DOMAIN\}'
  require_text "$LAPTOP_CADDYFILE" '^\*\.\{\$BASE_DOMAIN\}'
  require_text "$LAPTOP_COMPOSE_FILE" '127\.0\.0\.1:80:80'
  require_text "$LAPTOP_COMPOSE_FILE" '127\.0\.0\.1:443:443'
  require_text "$LAPTOP_COMPOSE_FILE" '127\.0\.0\.1:\$\{FRPS_BIND_PORT:-7000\}'
  require_text "$LAPTOP_COMPOSE_FILE" '127\.0\.0\.1:\$\{FRPS_HTTP_PORT:-8080\}'
  require_text "$LAPTOP_COMPOSE_FILE" '127\.0\.0\.1:\$\{FRPS_TCPMUX_PORT:-2022\}'
  require_text "$LAPTOP_COMPOSE_FILE" '127\.0\.0\.1:\$\{LAPTOP_SSH_PORT:-2222\}:2222'
  require_text "$LAPTOP_COMPOSE_FILE" 'PASSWORD_ACCESS: "false"'
  require_text "$LAPTOP_COMPOSE_FILE" '\./\.laptop-client/authorized_keys:/config/\.ssh/authorized_keys:ro'
  reject_text "$LAPTOP_COMPOSE_FILE" '0\.0\.0\.0'
  reject_text "$LAPTOP_COMPOSE_FILE" ':latest'

  rendered_config=$(compose config)
  printf '%s\n' "$rendered_config" | grep -Eq 'published: "80"' || fail "rendered laptop config must publish Caddy HTTP"

  host_ip_count=$(printf '%s\n' "$rendered_config" | grep -Ec '^[[:space:]]+host_ip: ' || true)
  loopback_host_ip_count=$(printf '%s\n' "$rendered_config" | grep -Ec '^[[:space:]]+host_ip: 127\.0\.0\.1$' || true)

  if [ "$host_ip_count" -eq 0 ]; then
    fail "rendered laptop config must explicitly bind published ports to loopback"
  fi

  if [ "$host_ip_count" -ne "$loopback_host_ip_count" ]; then
    fail "rendered laptop config must bind every published port to 127.0.0.1"
  fi

  for port in 80 443 "$(env_value FRPS_BIND_PORT)" "$(env_value FRPS_HTTP_PORT)" "$(env_value FRPS_TCPMUX_PORT)" "$(env_value LAPTOP_SSH_PORT)"; do
    printf '%s\n' "$rendered_config" | grep -Eq "published: \"?$port\"?" || fail "rendered laptop config must publish loopback port: $port"
  done

  echo "laptop mode validation passed"
}

validate_tls() {
  validate
  command -v curl >/dev/null 2>&1 || fail "curl is required for laptop TLS validation"
  command -v openssl >/dev/null 2>&1 || fail "openssl is required for laptop TLS validation"

  observation_suffix="$(date +%s)-$$"
  validation_host="tls-validate-$observation_suffix.localhost"

  api_request DELETE /_nixstasis/laptop/tls_observations >/dev/null

  for host in nixstasis.localhost auth.localhost frp-admin.localhost "$validation_host"; do
    status=$(https_check "$host" || true)

    case "$status" in
      200|302|401|403)
        ;;
      *)
        fail "unexpected HTTPS status for $host: ${status:-request failed}"
        ;;
    esac

    issuer=$(cert_issuer "$host" || true)
    printf '%s\n' "$issuer" | grep -Eq 'Caddy Local Authority|Caddy Local' || \
      fail "unexpected certificate issuer for $host: ${issuer:-missing issuer}"

    sans=$(cert_sans "$host" || true)
    printf '%s\n' "$sans" | grep -Eq "DNS:$host(,|$)" || \
      fail "certificate SANs for $host did not include requested host: ${sans:-missing SANs}"
  done

  observations=$(api_request GET /_nixstasis/laptop/tls_observations)
  printf '%s\n' "$observations" | grep -Eq "\"domain\":\"$validation_host\"" || \
    fail "TLS observations did not include unique validation ask call"

  echo "laptop TLS validation passed"
}

command_name="${1:-}"

if [ -z "$command_name" ]; then
  usage
  exit 2
fi

shift

case "$command_name" in
  start)
    validate
    compose up -d --build "$@"
    ;;
  stop)
    require_file "$ENV_FILE"
    compose down "$@"
    ;;
  validate)
    validate
    ;;
  validate-tls)
    validate_tls
    ;;
  *)
    usage
    exit 2
    ;;
esac
