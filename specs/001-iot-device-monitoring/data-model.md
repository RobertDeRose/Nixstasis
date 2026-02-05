# Data Model: IoT Device Monitoring

## Entities

### Device

Represents a physical IoT unit.

- **Table**: `devices`
- **Fields**:
  - `id` (UUID, PK)
  - `mac_address` (String, Unique, Indexed) - Physical identifier.
  - `product_name` (String, Indexed) - Grouping key from schema.
  - `approval_status` (Enum: `pending`, `approved`, `rejected`) - For US2 approval workflow.
  - `schema_definition` (JSONB) - The schema provided during registration.
  - `last_seen_at` (Timestamp) - Updated on heartbeat.
  - `metadata` (JSONB) - Current state/tags.

### Telemetry (Device Data)

Historical log of data reported by devices.

- **Table**: `telemetry_events`
- **Fields**:
  - `id` (UUID, PK)
  - `device_id` (UUID, FK -> devices.id)
  - `timestamp` (Timestamp, Indexed)
  - `payload` (JSONB) - The dynamic data reported. GIN Indexed.

### Heartbeat

Log of check-ins (optional, can be ephemeral or aggregated, but good for "offline" detection audit).

- **Table**: `heartbeats` (Optional, `last_seen_at` on Device might suffice for MVP, but Spec mentions "stopped polling
  after window").
- *Decision*: Use `last_seen_at` on `Device` for efficiency. If audit needed, log to `heartbeat_logs`.

### AlertRule

Configuration for data-driven alerts.

- **Table**: `alert_rules`
- **Fields**:
  - `id` (UUID, PK)
  - `name` (String)
  - `product_name` (String) - Applies to devices with this product.
  - `condition_field` (String) - JSON path (e.g., "temperature").
  - `operator` (Enum: `>`, `<`, `=`, `!=`)
  - `threshold_value` (String/Number)
  - `window_minutes` (Integer, Nullable) - For "Offline" alerts (special type).

### Alert

Generated events when rules are violated.

- **Table**: `alerts`
- **Fields**:
  - `id` (UUID, PK)
  - `device_id` (UUID, FK -> devices.id)
  - `rule_id` (UUID, FK -> alert_rules.id, Nullable for system alerts)
  - `type` (Enum: `offline`, `threshold`)
  - `status` (Enum: `active`, `resolved`, `acknowledged`)
  - `message` (String)
  - `triggered_at` (Timestamp)

### PendingCommand

Commands queued for devices.

- **Table**: `pending_commands`
- **Fields**:
  - `id` (UUID, PK)
  - `device_id` (UUID, FK -> devices.id)
  - `command_payload` (JSONB)
  - `status` (Enum: `queued`, `delivered`, `acked`)
  - `queued_at` (Timestamp)
  - `delivered_at` (Timestamp)

## Relationships

- `Device` (1) has (Many) `Telemetry`
- `Device` (1) has (Many) `Alerts`
- `Device` (1) has (Many) `PendingCommand`
- `AlertRule` (1) has (Many) `Alerts`

## JSONB Indexing Strategy

- `devices.schema_definition`: GIN index to query capability.
- `telemetry_events.payload`: GIN index to support `AlertRule` queries and Custom Reports.
