# Server Monitoring

The `Nixstasis.Monitoring` context: processing heartbeats, storing telemetry, alert rules and alerts, spotting offline
devices, and sending notifications. The telemetry size limits and the rules for webhook destinations are defined
here.

## Owns

- `Nixstasis.Monitoring` in `packages/server/lib/nixstasis/monitoring.ex`, and `Alert`, `AlertRule`, `Telemetry`,
  `RuleEvaluator`, and the limits in `telemetry_limits.ex` under `packages/server/lib/nixstasis/monitoring/`.
- The supervised `OfflineChecker` and `TelemetryRetentionWorker` ([Server Application](server-application.md)).
- Email and webhook delivery in `packages/server/lib/nixstasis/notifications/`.

## Entry points

- `heartbeat/2`, called by the heartbeat controller and the generated heartbeat action. It validates the telemetry,
  then updates `last_seen_at`, records SSH host keys and command inventory, persists telemetry, evaluates alert rules,
  and returns queued commands from [Server Devices](server-devices.md). The sequence is drawn in
  [Data Flow](../data-flow.md).
- `evaluate_telemetry/2` and `RuleEvaluator`, which turn telemetry into alerts.
- `check_offline_devices/1`, run periodically by `OfflineChecker` using the offline window from settings.
- Alert rule management: `list_rules/0`, `create_rule/1`, `update_rule/2`, `delete_rule/1`, and
  `list_rules_for_product/1`, used by the `/alerts/rules` LiveView.

## Boundaries

- **Telemetry limits:** persisted telemetry is capped at 65,536 encoded bytes, nesting depth 8, 512 total keys, 128 keys
  per object, 128 bytes per key, 256 items per array, and 16,384 bytes per string, and must contain only JSON values.
  The `Telemetry` resource enforces the same limits on every write. A heartbeat with rejected telemetry changes
  nothing: the device is not marked as seen, and no host key, inventory, alert, or command is processed.
- **Host keys during heartbeat:** a concurrent host-key change or persistence failure is logged and retried on the next
  heartbeat; it never blocks telemetry or commands.
- **Alert visibility:** active alerts are read with the operator's device scope, so scoped viewers see only alerts for
  their devices ([Server Domain](server-domain.md)). Alert rules are global and need the alert view or manage
  capability.
- **Offline window:** a positive whole number of minutes, 10 by default, validated by `SystemSetting` on every write
  path.
- **Webhook destinations:**
  - Must use HTTPS. Phoenix resolves the host before every delivery and rejects loopback, private, link-local, and
    reserved answers; any rejected answer blocks delivery even when public answers are present.
  - IPv6 destinations must fall in an IANA-allocated global-unicast range, excluding documentation, 6to4, and
    protocol-assignment ranges. The allocation table in `webhook.ex` follows the
    [IANA registry](https://www.iana.org/assignments/ipv6-unicast-address-assignments/); refresh it and its boundary
    tests when IANA publishes new allocations. IPv4-mapped addresses use the IPv4 checks.
  - The request is pinned to a validated address while keeping the original hostname for TLS verification and the
    `Host` header, and redirects are not followed. Each DNS lookup times out after five seconds.
- Admins change the offline window and notification destinations on the `/settings` page. Stored webhook URLs are never
  shown again; leaving the field blank keeps the current destination, and removal is explicit.
