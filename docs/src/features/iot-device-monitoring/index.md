# IoT Device Monitoring

## References

- Beads feature root: `nixstasis-8nc`
- Design record: [design.md](design.md)

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

## Test Coverage

- `packages/server/test/nixstasis/devices_test.exs` and `packages/server/test/nixstasis/devices_bdd_test.exs`:
  registration, approval, and credentials.
- `packages/server/test/nixstasis/devices/approval_test.exs`, `enrollment_test.exs`, and `schema_validator_test.exs`
  under the same directory: approval, enrollment, and schema validation.
- `packages/server/test/nixstasis/monitoring/heartbeat_test.exs`, `command_queue_test.exs`, `telemetry_test.exs`,
  `telemetry_limits_test.exs`, and `offline_checker_test.exs`: heartbeats, command claims, telemetry, and freshness.
- `packages/server/test/nixstasis/alerts_test.exs` and `packages/server/test/nixstasis/monitoring/alert_worker_test.exs`:
  alerts.
- `packages/server/test/nixstasis_web/controllers/device_controller_test.exs`,
  `heartbeat_controller_test.exs`, and `device_command_controller_test.exs`: device protocol endpoints and heartbeat
  authentication.
- `packages/server/test/nixstasis_web/plugs/rate_limiter_test.exs`: heartbeat rate limits.

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
