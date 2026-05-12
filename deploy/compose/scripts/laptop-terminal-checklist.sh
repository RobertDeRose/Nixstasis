#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMPOSE_DIR="$ROOT_DIR/deploy/compose"

cat <<EOF
Laptop terminal validation checklist
====================================

Prerequisites:
1. Copy deploy/compose/laptop.env.example to deploy/compose/laptop.env.
2. Replace all secrets, digests, and validation tokens in laptop.env.
3. Run deploy/compose/scripts/laptop-client.sh prepare.
4. Run deploy/compose/scripts/laptop.sh start.
5. Run deploy/compose/scripts/laptop-client.sh register.
6. Approve the registered device in https://nixstasis.localhost/devices.
7. Run deploy/compose/scripts/laptop-client.sh register again to persist the token.
8. Start polling with deploy/compose/scripts/laptop-client.sh poll.

Browser terminal journey:
1. Open https://nixstasis.localhost/devices.
2. Open the registered laptop test device.
3. Confirm remote access requests cause FRPC to start:
   - Optional: run deploy/compose/scripts/laptop-client.sh validate-frpc separately.
4. Open the browser terminal from /devices/:id.
5. Run: printf nixstasis-smoke
6. Confirm the terminal prints: nixstasis-smoke
7. Close the terminal.
8. Reopen the terminal for the same device.
9. Run: whoami
10. Confirm the terminal prints: nixstasis
11. Close the terminal again.

Expected path coverage:
- Browser UI and Phoenix LiveView open the remote-access lease.
- Phoenix Channel topic terminal:* is joined with an opaque session ref.
- Server-side ssh uses FRPS TCP mux through the configured proxy command.
- FRPC forwards the SSH connection to the laptop-ssh target.
- The command output returns to the browser terminal.

Use this checklist for T018 clean-state validation and attach screenshots/logs to
the run notes if the validation is executed manually.
EOF
