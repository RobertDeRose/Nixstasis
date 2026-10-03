#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
CLIENT_DIR="$ROOT_DIR/packages/client"
POSTINSTALL="$CLIENT_DIR/build/debian/postinstall.sh"
POLL_UNIT="$CLIENT_DIR/build/root-dir/lib/systemd/system/nixstasis-poll.service"
HELPER="$CLIENT_DIR/build/root-dir/usr/libexec/nixstasis/ssh-authorized-keys"
DROPIN="$CLIENT_DIR/build/root-dir/etc/ssh/sshd_config.d/nixstasis-support.conf"
GORELEASER="$CLIENT_DIR/.goreleaser.yaml"
VERIFY="$CLIENT_DIR/build/bin/verify_artifacts.sh"
DOCKERFILE="$CLIENT_DIR/Dockerfile"

fail() {
  echo "native packaging contract failed: $1" >&2
  exit 1
}

require_literal() {
  file="$1"
  text="$2"
  grep -Fq -- "$text" "$file" || fail "$file is missing: $text"
}

require_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

for file in "$POSTINSTALL" "$POLL_UNIT" "$HELPER" "$DROPIN" "$GORELEASER" "$VERIFY" "$DOCKERFILE"; do
  require_file "$file"
done

sh -n "$HELPER" "$VERIFY"
bash -n "$POSTINSTALL"

require_literal "$POSTINSTALL" 'groupadd --system "$group"'
require_literal "$POSTINSTALL" 'ensure_group nixstasis-ssh'
require_literal "$POSTINSTALL" 'useradd --system --no-create-home --home-dir /var/lib/empty'
require_literal "$POSTINSTALL" '--gid nixstasis-ssh nixstasis-ssh-authority'
require_literal "$POSTINSTALL" 'usermod --lock nixstasis-ssh-authority'
require_literal "$POSTINSTALL" 'usermod --append --groups nixstasis-ssh nixstasis'
require_literal "$POSTINSTALL" 'install -d -m 0750 -o nixstasis -g nixstasis-ssh /run/nixstasis'
require_literal "$POSTINSTALL" 'chown root:root /usr/libexec/nixstasis/ssh-authorized-keys'
require_literal "$POSTINSTALL" 'chmod 0644 /etc/ssh/sshd_config.d/nixstasis-support.conf'
require_literal "$POSTINSTALL" '"$sshd_bin" -t'
require_literal "$POSTINSTALL" 'systemctl reload sshd.service'
require_literal "$POSTINSTALL" 'systemctl reload ssh.service'
require_literal "$POSTINSTALL" 'systemctl daemon-reload'

require_literal "$POLL_UNIT" 'User=nixstasis'
require_literal "$POLL_UNIT" 'Group=nixstasis-ssh'
require_literal "$POLL_UNIT" 'SupplementaryGroups=nixstasis'
require_literal "$POLL_UNIT" 'RuntimeDirectory=nixstasis'
require_literal "$POLL_UNIT" 'RuntimeDirectoryMode=0750'

require_literal "$GORELEASER" 'openssh-server'
require_literal "$VERIFY" 'usr/libexec/nixstasis/ssh-authorized-keys'
require_literal "$VERIFY" 'etc/ssh/sshd_config.d/nixstasis-support.conf'
require_literal "$VERIFY" 'lib/systemd/system/nixstasis-poll.service'
require_literal "$HELPER" 'exec /usr/bin/nixstasis ssh-authorized-keys "$@"'
if grep -Fq 'NIXSTASIS_SSH_AUTHORITY_SOCKET' "$HELPER"; then
  fail "$HELPER must use the fixed trusted socket path"
fi

require_literal "$DOCKERFILE" 'passwd --lock nixstasis-ssh-authority'
require_literal "$DOCKERFILE" 'install -d -m 0750 -o nixstasis -g nixstasis-ssh /run/nixstasis'
require_literal "$DOCKERFILE" 'usermod --append --groups nixstasis-ssh nixstasis'

[ -x "$HELPER" ] || fail "helper must be executable in source tree"
[ "$(stat -f '%Lp' "$HELPER" 2>/dev/null || stat -c '%a' "$HELPER")" = 755 ] ||
  fail "helper must be mode 0755 in source tree"
[ "$(stat -f '%Lp' "$DROPIN" 2>/dev/null || stat -c '%a' "$DROPIN")" = 644 ] ||
  fail "sshd drop-in must be mode 0644 in source tree"

echo "native packaging contract passed"
