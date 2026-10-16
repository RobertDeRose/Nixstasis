# In-Memory SSH Authorized Keys

## References

- Beads feature root: `nixstasis-bdv`
- Design record: [design.md](design.md)

## Delivered Capability

Browser-terminal SSH authorization now uses OpenSSH `AuthorizedKeysCommand` and
an in-memory, TTL-bound authorization store in the Go client. The server queues
versioned `ssh_authorize` and `ssh_revoke` commands, targets the dedicated
`nixstasis-support` account, and exposes the terminal socket only after the
matching authorization result is acknowledged.

The installed helper and client use the fixed local socket
`/run/nixstasis/ssh-authority.sock`. Native packages and the Compose image
provision separate `nixstasis`, `nixstasis-support`, and locked
`nixstasis-ssh-authority` identities. Browser-terminal keys are not written to
persistent `authorized_keys` files.

## User-Facing Behavior

- A terminal session authenticates as `nixstasis-support` through the existing
  FRP/OpenSSH path.
- The browser terminal does not receive a socket token until the matching
  dynamic `ssh_authorize` command returns `OK`.
- Positive, bounded TTLs, matching session refs, canonical public-key material,
  and the exact versioned content types are required.
- Unknown, expired, revoked, malformed, wrong-user, unavailable, and mismatched
  keys fail closed without printing an authorized key.
- Terminal close, failed joins, authorization timeout, offline transitions, SSH
  startup failure, and lease expiry clear server key material first and queue a
  bounded, idempotent revoke when possible.
- Client restart empties the in-memory store and invalidates browser-terminal
  authorizations.

## Design Integration

Phoenix remains authoritative for operator authorization, terminal session
lifecycle, and server-side private-key material. The Go client is authoritative
for device-local key validation, TTL expiry, revocation, and IPC responses.
OpenSSH enforces login for `nixstasis-support`; the helper is only an adapter and
FRP remains transport. No capability negotiation, TCP IPC, persistent-key
fallback, or broader helper privilege was introduced.

## Operational Impact

Installers and the Compose client provision the support account, locked helper
identity, socket group, runtime directory, root-owned helper, and OpenSSH
configuration. The helper and client must be available for support SSH login;
missing client or IPC state denies authentication rather than falling back to a
file. The supported IPC path is fixed at
`/run/nixstasis/ssh-authority.sock`; non-default runtime socket settings are
ignored with a warning. In the nested-systemd Compose client, an unprivileged
poll service falls back to a poll-owned, one-hour-bounded FRP session when the
system manager denies `systemd-run`; native root-managed installations retain
the transient systemd unit path.

The host real-sshd integration is focused Linux coverage. The separate
Compose/browser smoke exercises the support-account login, safe diagnostic,
terminal close, FRP cleanup, and post-revoke helper denial in a configured lab.

## Reference and Contracts

- [API & Runtime Contracts](../../reference/contracts.md#browser-terminal-ssh-authorization-contract)
- [Client-Server Interface](../../client-server-interface.md)
- [Data Flow](../../data-flow.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
- [Server Devices](../../modules/server-devices.md)
- [Client Command Handler](../../modules/client-command-handler.md)
- [Client FRP Manager](../../modules/client-frp-manager.md)
- [Client Transport](../../modules/client-transport.md)
- [Deployment Compose](../../modules/deployment-compose.md)
- [OpenAPI Contracts](../../reference/openapi/device-api.yaml)
- Client installation and packaging: `packages/client/README.md`
- Compose deployment details: `deploy/compose/README.md`

## Test Coverage

- Client in-memory store, key validation, and IPC: `packages/client/internal/sshauth/store_test.go`,
  `packages/client/internal/sshauth/keys_test.go`, and `packages/client/internal/sshauth/ipc_test.go`.
- `packages/client/internal/sshauth/sshd_integration_test.go`: host real-sshd `AuthorizedKeysCommand` integration
  (Linux only).
- `packages/client/cmd/nixstasis/ssh_authorized_keys_test.go`: the `AuthorizedKeysCommand` helper.
- `packages/client/internal/commands/handler_test.go`: dynamic `ssh_authorize` and `ssh_revoke` command handling.
- `packages/client/cmd/nixstasis/poll_test.go`: the fixed trusted IPC socket path.
- `packages/client/build/tests/native_packaging_test.sh`: native installer accounts, socket group, runtime directory,
  helper permissions, and sshd configuration.
- `packages/server/test/nixstasis/devices/ssh_client_test.exs` and
  `packages/server/test/nixstasis/devices/ssh_key_manager_test.exs`: server key material and SSH client behavior.
- `packages/server/test/nixstasis/devices_test.exs`: command queueing and terminal authorization status.
- `packages/server/test/nixstasis_web/controllers/heartbeat_controller_test.exs`: dynamic `ssh_authorize` payload
  serialization.
- `packages/server/test/nixstasis_web/channels/terminal_channel_test.exs` and
  `packages/server/test/nixstasis_web/live/device_live_test.exs`: terminal acknowledgement gating and cleanup.
- `packages/server/test/nixstasis/repo/migrations/deduplicate_terminal_revokes_test.exs`: the terminal-revoke
  migration regression.
- `deploy/compose/scripts/ssh_terminal_smoke.sh`: the Compose/browser terminal smoke, which verifies support-account
  login, terminal close, revoke acknowledgement, and helper denial of the revoked key.

## Design Reconciliation

### Delivered as Designed

- Dynamic in-memory authorization is the only browser-terminal key path.
- The server uses exact versioned `ssh_authorize` and `ssh_revoke` contracts,
  top-level `public_key`, matching session refs, bounded TTLs, and the
  `nixstasis-support` target.
- Terminal activation is gated on the matching acknowledged command, and all
  specified cleanup boundaries clear server key material before best-effort
  revoke.
- The client/helper IPC boundary is local-only, bounded, fail-closed, and fixed
  at `/run/nixstasis/ssh-authority.sock`.
- Native installers and the container preserve separate service, support, and
  locked helper identities without deleting operator-owned key files.

### Intentional Changes

- The implementation selected one fixed trusted socket path instead of allowing
  a configurable runtime path, preventing poll/helper drift and untrusted path
  selection.
- Host real-sshd integration and Compose/browser smoke are recorded as separate
  evidence classes; the former does not claim the latter.
- Nested-systemd Compose clients use a bounded poll-owned FRP session when the
  unprivileged poll service cannot create a system transient unit; native
  root-managed systemd remains the primary lifecycle path.
- The terminal-revoke migration now removes older duplicate revoke rows before
  creating its uniqueness constraint, preserving unrelated command rows.
- The reader-facing command contract is maintained in reference/OpenAPI docs,
  while the design remains planning authority.

### Deferred Work

- No feature-scope behavior is deferred.

### Rejected or Removed Scope

- Persistent browser-terminal `authorized_keys` files.
- File-based fallback, capability negotiation, TCP IPC, password login, or a
  privileged/general-purpose helper command path.
- Replacing FRP or changing the Phoenix/Caddy operator authorization boundary.

## Documentation Updated

- `docs/src/features/in-memory-ssh-authorized-keys/design.md`
- `docs/src/features/in-memory-ssh-authorized-keys/index.md`
- `docs/src/SUMMARY.md`
- `docs/src/features/index.md`
- `docs/src/planned-features.md`
- `docs/src/client-server-interface.md`
- `docs/src/data-flow.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/modules/client-command-handler.md`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/modules/server-devices.md`
- `docs/src/reference/contracts.md`
- `docs/src/reference/openapi/device-api.yaml`
- `docs/src/reference/openapi/index.md`
- `packages/client/README.md`
- `deploy/compose/README.md`
- `packages/client/internal/frp/manager.go`
- `packages/server/priv/repo/migrations/20260803120000_deduplicate_terminal_revokes.exs`
