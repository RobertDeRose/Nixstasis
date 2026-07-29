# IoT Device Monitoring

## Delivery Summary

- Beads feature root: `nixstasis-8nc`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `fce8833b7ba9d7521ba56407689520a9aa938a17`
- Design record: `design.md`

## Delivered Capability

Nixstasis provides device registration and approval, persistent device credentials, authenticated heartbeats, dynamic
telemetry, command delivery, offline detection, alerts, and reusable reporting over product-specific schemas.

## User-Facing Behavior

Integrators register devices with product schemas; administrators approve pending devices; operators monitor freshness,
queue commands, manage alerts, and inspect reports derived from telemetry.

## Design Integration

Ash resources and server contexts own durable device, telemetry, command, alert, report, and settings data. Bespoke
device protocol controllers preserve the stable Go client contract and enforce device-token boundaries.

## Operational Impact

Heartbeat rate limits, freshness windows, atomic command claims, schema validation, and explicit authorization failures
protect fleet monitoring under retries and concurrent polling.

## Reference and Contracts

- [Data Flow](../../data-flow.md)
- [Client-Server Interface](../../client-server-interface.md)
- [Server Devices](../../modules/server-devices.md)
- [Server Monitoring](../../modules/server-monitoring.md)

## Validation Evidence

Device domain and controller tests cover registration, approval, credentials, heartbeat authentication, command claims,
telemetry, rate limits, alerts, and schema validation. `packages/server/lib/nixstasis/devices.ex` corroborates the core
context.

## Design Reconciliation

### Delivered as Designed

The full registration-to-monitoring lifecycle and its dynamic telemetry model were delivered.

### Intentional Changes

Builder contracts and authorization boundaries were later hardened while retaining the device protocol.

### Deferred Work

Future fleet organization and curated package catalogs remain separate planned features.

### Rejected or Removed Scope

No unauthenticated heartbeat or implicit schema fallback remains supported.

## Documentation Updated

- `docs/src/data-flow.md`
- `docs/src/client-server-interface.md`
- `docs/src/modules/server-devices.md`
- `docs/src/modules/server-monitoring.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-8nc`. Commit `fce8833b7ba9d7521ba56407689520a9aa938a17`
directly aligned public registration validation with the delivered monitoring contract.
