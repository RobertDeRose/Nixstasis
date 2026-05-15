#!/bin/sh

set -eu

FORCE_CONFIG=false

usage() {
  cat <<'EOF'
Usage: install.sh [--force-config]

Installs the Nixstasis client bundle to system paths.

Options:
  --force-config  overwrite existing /etc/nixstasis/config.yaml
  -h, --help      show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force-config) FORCE_CONFIG=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$(id -u)" -ne 0 ]; then
  echo "install.sh must be run as root" >&2
  exit 1
fi

if [ ! -d /run/systemd/system ]; then
  echo "install.sh requires a running systemd host" >&2
  exit 1
fi

install_file() {
  src="$1"
  dst="$2"
  mode="$3"

  install -D -m "$mode" "$src" "$dst"
  echo "installed $dst"
}

install_config() {
  src="$1"
  dst="$2"
  mode="$3"

  if [ -e "$dst" ] && [ "$FORCE_CONFIG" != true ]; then
    echo "preserved existing $dst"
    return
  fi

  install_file "$src" "$dst" "$mode"
}

install_file nixstasis /usr/bin/nixstasis 0755
install_file frpc /usr/libexec/nixstasis/frpc 0755
install_file frpc.toml /usr/share/nixstasis/frpc.toml 0644
install_file config.example.yaml /usr/share/nixstasis/config.example.yaml 0644
install_config config.example.yaml /etc/nixstasis/config.yaml 0644
if [ -e /etc/nixstasis/frpc.toml ]; then
  echo "warning: /etc/nixstasis/frpc.toml is no longer read; move custom values into /etc/nixstasis/config.yaml" >&2
fi
install_file nixstasis-poll.service /lib/systemd/system/nixstasis-poll.service 0644
install_file nixstasis-poll.path /lib/systemd/system/nixstasis-poll.path 0644
install_file nixstasis-registration.service /lib/systemd/system/nixstasis-registration.service 0644

systemctl daemon-reload
echo "reloaded systemd unit files"

INSTALLED_VERSION=""
if [ -f artifacts.json ] && command -v python3 >/dev/null 2>&1; then
  if ! INSTALLED_VERSION=$(python3 -c "import json; print(json.load(open('artifacts.json', encoding='utf-8'))['version'])" 2>/dev/null); then
    echo "warning: unable to read installer version from artifacts.json" >&2
    INSTALLED_VERSION=""
  fi
fi

cat <<EOF

Nixstasis client${INSTALLED_VERSION:+ $INSTALLED_VERSION} is installed.

Next steps:
  1. Review /etc/nixstasis/config.yaml.
  2. Run: systemctl enable nixstasis-registration.service nixstasis-poll.path
  3. Run: systemctl start nixstasis-registration.service nixstasis-poll.path
EOF
