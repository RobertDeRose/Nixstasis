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

port_names="FRPS_BIND_PORT FRPS_DASHBOARD_PORT FRPS_TCPMUX_PORT FRPS_HTTP_PORT"
string_names="FRPS_DASHBOARD_USER FRPS_DASHBOARD_PASSWORD BASE_DOMAIN"

# Check the template, not the rendered output, for placeholders this renderer
# does not fill: the output holds operator credentials, which must never be
# scanned for placeholder-shaped text or echoed to the log.
known_placeholders=""
for name in $port_names $string_names; do
  known_placeholders="$known_placeholders -e __${name}__"
done
# shellcheck disable=SC2086
unknown_placeholders=$(grep -oE '__[A-Z0-9_]+__' "$template" | sort -u |
  grep -vxF $known_placeholders || true)
if [ -n "$unknown_placeholders" ]; then
  printf '%s\n' "$unknown_placeholders" >&2
  echo "$template has placeholders this renderer does not fill" >&2
  exit 1
fi

: "${FRPS_DASHBOARD_USER:?FRPS_DASHBOARD_USER is required}"
: "${FRPS_DASHBOARD_PASSWORD:?FRPS_DASHBOARD_PASSWORD is required}"
: "${BASE_DOMAIN:?BASE_DOMAIN is required}"

for port_name in $port_names; do
  eval "port_value=\${$port_name:-}"
  case "$port_value" in
    '' | *[!0-9]*)
      echo "$port_name must be numeric" >&2
      exit 1
      ;;
  esac
done

newline=$(printf '\nx')
newline=${newline%x}
for name in $string_names; do
  eval "value=\${$name}"
  case "$value" in
    *"$newline"*)
      echo "$name must not contain a newline" >&2
      exit 1
      ;;
  esac
  # A TOML basic string cannot carry control characters other than tab.
  if printf '%s' "$value" | LC_ALL=C tr -d '\t' | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "$name must not contain control characters" >&2
    exit 1
  fi
  # The sed expressions below run in sequence over each line, so a value that
  # holds a placeholder would be rewritten by that placeholder's expression.
  for other in $port_names $string_names; do
    case "$value" in
      *"__${other}__"*)
        echo "$name must not contain the template variable __${other}__" >&2
        exit 1
        ;;
    esac
  done
done

# Encode a value as the body of a TOML basic string, then escape the result
# for use as a sed replacement. TOML needs backslash and double quote escaped;
# sed needs backslash, slash, and ampersand escaped in the replacement text.
escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | sed 's/[\/&\\]/\\&/g'
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
