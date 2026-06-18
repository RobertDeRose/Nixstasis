#!/bin/sh

set -eu

addr="${NIXSTASIS_SIMULATOR_HTTP_ADDR:-127.0.0.1}"
port="${NIXSTASIS_SIMULATOR_HTTP_PORT:-443}"
runtime_dir="${NIXSTASIS_SIMULATOR_HTTP_RUNTIME_DIR:-/run/nixstasis/simulator-http}"

case "$port" in
  ''|*[!0-9]*)
    echo "NIXSTASIS_SIMULATOR_HTTP_PORT must be numeric" >&2
    exit 1
    ;;
esac

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required for the simulator HTTPS endpoint" >&2
  exit 1
}

mkdir -p "$runtime_dir"
chmod 700 "$runtime_dir"

cert_file="$runtime_dir/cert.pem"
key_file="$runtime_dir/key.pem"
response_file="$runtime_dir/response.http"

if [ ! -s "$cert_file" ] || [ ! -s "$key_file" ]; then
  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -nodes \
    -keyout "$key_file" \
    -out "$cert_file" \
    -subj "/CN=localhost" \
    -days 1 >/dev/null 2>&1
  chmod 600 "$key_file"
  chmod 644 "$cert_file"
fi

host_name=$(hostname 2>/dev/null || printf 'nixstasis-simulator')

{
  printf 'HTTP/1.1 200 OK\r\n'
  printf 'Content-Type: text/plain; charset=utf-8\r\n'
  printf 'Connection: close\r\n'
  printf '\r\n'
  printf 'nixstasis simulator %s\n' "$host_name"
} > "$response_file"

while :; do
  openssl s_server \
    -quiet \
    -accept "$addr:$port" \
    -cert "$cert_file" \
    -key "$key_file" \
    -ign_eof < "$response_file"

  sleep 1
done
