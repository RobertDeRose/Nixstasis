# Server-Provided FRPS Token

## Delivery Summary

- Beads feature root: `nixstasis-5hx`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `8d4c10618c56a1412f29bfda1f08d77c88ed03bf`
- Design record: `design.md`

## Delivered Capability

Authenticated heartbeat responses carry the FRPS token only while remote access is requested. The Go client uses token
presence as the FRPC lifecycle signal and supplies the secret through the transient systemd unit credential path.

## User-Facing Behavior

Remote access starts when the server returns a non-empty token and stops when the token is absent. Operators no longer
configure the shared FRPS token in static client configuration.

## Design Integration

Phoenix and FRPS receive the same deployment secret, while device API credentials remain separate. FRPC lifecycle stays
inside the client manager and the existing client-owned template expansion model.

## Operational Impact

A missing server token prevents tunnel startup without breaking heartbeat processing. Shared-token rotation remains a
fleet-wide operation under the current upstream FRP authentication model.

## Reference and Contracts

- [Client-Server Interface](../../client-server-interface.md)
- [Client FRP Manager](../../modules/client-frp-manager.md)
- [Deployment Compose](../../modules/deployment-compose.md)

## Validation Evidence

Client polling and transport tests cover token-present and token-absent behavior; server controller tests cover
conditional response rendering; the Compose runtime-contract check verifies shared configuration.

## Design Reconciliation

### Delivered as Designed

The boolean trigger was replaced by a token-bearing contract without persisting the FRPS secret on managed clients.

### Intentional Changes

Later client work derives FRP route identity from the server-assigned device UUID while retaining token semantics.

### Deferred Work

Per-device FRPS credentials and independent revocation remain deferred.

### Rejected or Removed Scope

The feature did not replace FRP authentication or alter browser and terminal authorization.

## Documentation Updated

- `docs/src/client-server-interface.md`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/deployment-compose.md`
- `deploy/compose/README.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-5hx`. Commit `8d4c10618c56a1412f29bfda1f08d77c88ed03bf`
directly implemented heartbeat-provided FRPS token handling in the client polling path.
