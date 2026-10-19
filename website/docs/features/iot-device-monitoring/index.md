# IoT Device Monitoring

The core of Nixstasis: devices register and wait for approval, keep lasting credentials, send authenticated heartbeats
with telemetry in their own format, receive commands, and are marked offline when they go quiet. Operators get alerts,
and reports that work across each product's schema. The original plan is in the [design record](design.md).

## What changed for users

- **Integrators** register devices along with their product's telemetry schema.
- **Administrators** approve devices that are waiting.
- **Operators** see which devices are checking in, queue commands, manage alerts, and read reports built from
  telemetry.

## How it fits in

Ash resources and the server contexts store devices, telemetry, commands, alerts, reports, and settings. Purpose-built
controllers serve the device protocol, so the client's API stays stable, and every device request is checked against
its own token.

## Running it

Heartbeat rate limits, freshness windows, commands that are claimed once and only once, schema checks, and clear
authorization errors keep monitoring reliable when devices retry or poll at the same time.

## Differences from the design

Builder contracts and permission checks were tightened later, without changing the device protocol.

## Not included

- Every heartbeat must be authenticated.
- A device must send a schema; there is no fallback schema.

## Tests

- `packages/server/test/nixstasis/devices_test.exs` and `devices_bdd_test.exs`: registration, approval, and credentials.
- `packages/server/test/nixstasis/devices/approval_test.exs`, `enrollment_test.exs`, and `schema_validator_test.exs`:
  approval, enrollment, and schema checks.
- `packages/server/test/nixstasis/monitoring/heartbeat_test.exs`, `command_queue_test.exs`, `telemetry_test.exs`,
  `telemetry_limits_test.exs`, and `offline_checker_test.exs`: heartbeats, command claims, telemetry, and offline
  detection.
- `packages/server/test/nixstasis/alerts_test.exs` and `packages/server/test/nixstasis/monitoring/alert_worker_test.exs`:
  alerts.
- `packages/server/test/nixstasis_web/controllers/device_controller_test.exs`, `heartbeat_controller_test.exs`, and
  `device_command_controller_test.exs`: the device protocol and heartbeat authentication.
- `packages/server/test/nixstasis_web/plugs/rate_limiter_test.exs`: heartbeat rate limits.

## Related pages

- [Data Flow](../../data-flow.md)
- [Client-Server Interface](../../client-server-interface.md)
- [Server Devices](../../modules/server-devices.md)
- [Server Monitoring](../../modules/server-monitoring.md)
