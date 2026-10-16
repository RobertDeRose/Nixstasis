# Server-Provided FRPS Token

## References

- Beads feature root: `nixstasis-5hx`
- Design record: [design.md](design.md)

## Delivered Capability

Authenticated heartbeat responses carry a signed, device/lease-bound FRPS credential only while a selected durable lease is authorized. The Go client uses token
presence as the FRPC lifecycle signal and supplies the secret through a root-only session environment file.

## User-Facing Behavior

Remote access starts when the server returns a non-empty token and stops when the token is absent. Operators no longer
configure a deployment-wide FRPS credential in static client configuration.

## Design Integration

Phoenix signs a short-lived device credential and FRPS validates it through the internal `Login`/`NewProxy` authorization
plugin. FRPC lifecycle stays inside the client manager and the existing client-owned template expansion model.

## Operational Impact

The deployment-wide FRPS client secret has been removed. Device credentials are session-bounded and signed from
`SECRET_KEY_BASE`; FRPS rejects credentials and proxy registrations that do not match the device identity.

## Reference and Contracts

- [Client-Server Interface](../../client-server-interface.md)
- [Client FRP Manager](../../modules/client-frp-manager.md)
- [Deployment Compose](../../modules/deployment-compose.md)

## Test Coverage

- `packages/client/cmd/nixstasis/poll_test.go` and `packages/client/internal/transport/client_runtime_test.go`:
  token-present and token-absent FRPC lifecycle, and lease replacement versus signature-only rotation.
- `packages/server/test/nixstasis_web/controllers/heartbeat_controller_test.exs`: signed, lease-bound credentials in
  heartbeat responses.
- `packages/server/test/nixstasis_web/controllers/frp_authorization_controller_test.exs` and
  `packages/server/test/nixstasis_web/controllers/frp_access_controller_test.exs`: FRPS `Login`/`NewProxy`
  authorization and cross-device proxy rejection.
- `packages/server/test/nixstasis/devices/remote_access_leases_test.exs`: durable lease identity, ownership,
  precedence, revocation, and projection consistency.
- `deploy/compose/scripts/check_frps_config.sh` renders the Compose `frps.toml` template, plugin entry included, and
  verifies it with the pinned frps binary.
- `mix ash.codegen --check` guards the durable lease resource and its migrations.

## Design Reconciliation

### Delivered as Designed

The boolean trigger was replaced by a token-bearing contract without persisting the FRPS secret on managed clients.

### Intentional Changes

Security hardening now derives FRP route identity from the server-assigned device UUID, uses signed per-device
credentials, and authorizes FRPS `Login` and `NewProxy` operations through Phoenix.

### Current Lease Contract

Each lease persists its identity, owner, immutable profile, expiry, and
revocation independently. Device
fields are projections rather than authorization sources. Provisioning uses its
delivery UUID to recover the same lease after restart; it cannot silently renew
or close another operator's authorization.

Provisioning takes precedence over browser/direct leases; newest creation wins
within each class. The selected lease supplies both profile and lifetime. FRPS
checks that exact lease for new Login/NewProxy operations, so another live lease
cannot validate a revoked credential. Heartbeats advertise `remote_access_lease_id`
and `remote_access_expires_at_ms`; the client replaces a changed lease without
signature-only restart churn. Old unowned device-summary credentials fail closed.
Unrelated device updates cannot overwrite lease projections, and profile
preferences are reconciled within the same locked update transaction.

### Deferred Work

Established FRPS tunnels are stopped through the next authenticated heartbeat;
instant server-side tunnel teardown is not part of this correction.

### Rejected or Removed Scope

Browser and terminal authorization remain separate from FRPS client authorization.

## Documentation Updated

- `docs/src/operations/secret-rotation.md`
- `docs/src/planned-features.md`
- `docs/src/client-server-interface.md`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/deployment-compose.md`
- `deploy/compose/README.md`
