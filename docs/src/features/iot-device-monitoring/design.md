# IoT Device Monitoring

## Feature Name

`iot-device-monitoring`

## Goal

Provide the core server-side monitoring system for Nixstasis-managed devices.
Devices self-register with dynamic product schemas, move through an approval
workflow, send authenticated heartbeats with telemetry, receive pending commands,
and feed alerting and reporting workflows.

## Users

- Device integrators registering hardware with Nixstasis.
- Administrators approving devices and monitoring fleet health.
- Operators delivering commands and remote-access intent through heartbeat responses.
- Analysts building alert rules and custom reports from device telemetry.

## Requirements

- Devices register with a unique MAC address, product name, schema, and optional metadata.
- Registration schemas must include top-level `product`; missing or empty schemas are rejected.
- Re-registration by the same MAC address updates the existing device schema and metadata.
- Registration returns persistent API credentials for subsequent device calls.
- Unknown devices are recorded as pending until approved by an administrator.
- Heartbeats update `last_seen_at`, accept telemetry, and return pending commands.
- Heartbeats are authenticated with the persistent API token and rate limited per device.
- Offline alerts are generated from the configured heartbeat window.
- Alert rules evaluate dynamic telemetry fields for configured products.
- Alert notifications can be surfaced in the dashboard and dispatched through email or webhook destinations.
- Custom reports can select JSONB-backed telemetry fields across products.
- Report builder field-type conflicts require explicit user handling before save.

## Proposed Design

### Registration And Approval

Registration stores each device in `devices` with `mac_address`, `product_name`,
`schema_definition`, metadata, approval state, API token hash, and last-seen state.
Unknown devices enter pending approval. Approved devices can complete the normal
heartbeat and command workflow.

### Heartbeat And Commands

Approved devices send authenticated heartbeats to the device-specific heartbeat
endpoint. The server updates connectivity state, stores telemetry when present,
evaluates alert rules, and returns queued commands. Empty command queues return a
lightweight acknowledgement. When remote access is requested and configured, the
heartbeat response can include `remote_access_token` for FRPC authentication.

### Alerts And Reports

Offline monitoring compares `last_seen_at` with the configured offline window.
Data-driven alert rules bind product, JSON path, operator, and threshold.
Reports query telemetry payloads through JSONB paths and save reusable report
definitions.

## Data Model

- `devices`: identity, product, approval status, schema, metadata, token hash,
  remote-access state, and `last_seen_at`.
- `telemetry_events`: device reference, timestamp, and JSONB payload.
- `pending_commands`: device reference, command payload, status, and delivery timestamps.
- `alert_rules`: product, field path, operator, threshold, and rule metadata.
- `alerts`: device reference, optional rule reference, type, status, message, and trigger time.
- `custom_reports`: saved report configuration and query metadata.
- `system_settings`: global monitoring windows and notification destinations.

## Edge Cases

- Duplicate or conflicting schema keys must not silently break saved reports.
- Heartbeats for unregistered or unauthorized devices are rejected.
- Heartbeat surges are rate limited with HTTP 429 responses.
- Missing telemetry fields must not crash alert evaluation or report rendering.
- Incompatible report field types require explicit user resolution.

## Validation

- Registration accepts valid schemas and rejects missing `product`.
- Pending devices appear in the approval workflow and can be approved.
- Heartbeats update last-seen state, return commands, enforce token auth, and rate limit overload.
- Offline alerts are generated within the configured threshold behavior.
- Alert rules and reports operate over dynamic telemetry fields.
