#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
CLIENT_DIR="$ROOT_DIR/packages/client"

fail() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: deploy/compose/scripts/ssh_terminal_smoke.sh [-v]

Runs the real-sshd integration test that exercises the in-memory SSH
authorization pipeline end-to-end (sshd -> nixstasis ssh-authorized-keys ->
sshauth Unix socket -> in-memory store, with allow / unknown / expired /
revoked / wrong-user flows).

The test builds a throwaway nixstasis binary, forks a real sshd on a
high loopback port, and runs the system ssh client against it. It is
Linux-only (CI). macOS developer workstations skip with a clear message.

Examples:
  deploy/compose/scripts/ssh_terminal_smoke.sh
  deploy/compose/scripts/ssh_terminal_smoke.sh -v
EOF
}

verbose=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--verbose)
      verbose=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

command -v go >/dev/null 2>&1 || fail "go is required to run the ssh terminal smoke test"
[ -d "$CLIENT_DIR" ] || fail "missing client directory: $CLIENT_DIR"

cd "$CLIENT_DIR"

if [ -z "${GOEXPERIMENT:-}" ]; then
  export GOEXPERIMENT=jsonv2
fi

go_test_args="-count=1 -run TestRealSSHDIntegration\$ ./internal/sshauth/..."
if [ "$verbose" -eq 1 ]; then
  go_test_args="-v $go_test_args"
fi

echo "Running: go test $go_test_args"
GOEXPERIMENT="$GOEXPERIMENT" go test $go_test_args

cat <<EOF
ssh terminal smoke: PASS
EOF
