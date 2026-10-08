# Server-Provided FRPS Token

## Delivery Summary

- Beads feature root: `nixstasis-5hx`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `8d4c10618c56a1412f29bfda1f08d77c88ed03bf`
- Design record: `design.md`

## Delivered Capability

Authenticated heartbeat responses carry a signed, device-bound FRPS credential only while remote access is requested. The Go client uses token
presence as the FRPC lifecycle signal and supplies the secret through the transient systemd unit credential path.

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

### Deferred Work

Remote-access lease expiry is durable: Phoenix persists an absolute expiry and audit
owner, restores only unexpired leases after restart, refuses to mint FRPS
credentials after that persisted expiry, and caps each signed credential at the
lease expiry or signing maximum age, whichever is earlier. Heartbeats advertise
`remote_access_expires_at_ms` for client renewal without signature-only restart
churn. FRPS checks current persisted authorization for new Login/NewProxy operations,
so closing the lease blocks reuse of an outstanding credential.

### Rejected or Removed Scope

Browser and terminal authorization remain separate from FRPS client authorization.

## Documentation Updated

- `docs/src/client-server-interface.md`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/deployment-compose.md`
- `deploy/compose/README.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-5hx`. Commit `8d4c10618c56a1412f29bfda1f08d77c88ed03bf`
directly implemented heartbeat-provided FRPS token handling in the client polling path.
