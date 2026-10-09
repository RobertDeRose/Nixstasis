# Server-Provided FRPS Token

## Delivery Summary

- Beads feature root: `nixstasis-5hx`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `8d4c10618c56a1412f29bfda1f08d77c88ed03bf`
- Design record: `design.md`

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

## Validation Evidence

Client polling and transport tests cover token-present and token-absent behavior; server controller tests cover
signed credential and cross-device proxy rejection; the Compose runtime-contract check verifies the FRPS plugin wiring.

## Design Reconciliation

### Delivered as Designed

The boolean trigger was replaced by a token-bearing contract without persisting the FRPS secret on managed clients.

### Intentional Changes

Security hardening now derives FRP route identity from the server-assigned device UUID, uses signed per-device
credentials, and authorizes FRPS `Login` and `NewProxy` operations through Phoenix.

### Current Lease Contract

PR #3's approved lifecycle correction (`nixstasis-n01`) persists each lease's
identity, owner, immutable profile, expiry, and revocation independently. Device
fields are projections rather than authorization sources. Provisioning uses its
delivery UUID to recover the same lease after restart; it cannot silently renew
or close another operator's authorization.

Provisioning takes precedence over browser/direct leases; newest creation wins
within each class. The selected lease supplies both profile and lifetime. FRPS
checks that exact lease for new Login/NewProxy operations, so another live lease
cannot validate a revoked credential. Heartbeats advertise `remote_access_lease_id`
and `remote_access_expires_at_ms`; the client replaces a changed lease without
signature-only restart churn. Old unowned device-summary credentials fail closed.

### Deferred Work

Established FRPS tunnels are stopped through the next authenticated heartbeat;
instant server-side tunnel teardown is not part of this correction.

### Rejected or Removed Scope

Browser and terminal authorization remain separate from FRPS client authorization.

## Documentation Updated

- `docs/src/planned-features.md`
- `docs/src/client-server-interface.md`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/deployment-compose.md`
- `deploy/compose/README.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-5hx`. Commit `8d4c10618c56a1412f29bfda1f08d77c88ed03bf`
directly implemented heartbeat-provided FRPS token handling in the client polling path.
The user approved the durable per-lease redesign during PR #3 review; acceptance,
independent review, migration, and validation evidence are tracked by `nixstasis-n01`.
PR #3 review item 31 reconciles the completed roadmap entry with the current
lease-bound credential and internal authorization plugin contract (`nixstasis-yeo`).
