# Server Domain

## Language

- Elixir.

## Runtime Context

- Server domain/data layer.
- Ash domain with JSON:API and Phoenix integration.

## Purpose

- Defines domain resources, resource action functions, and Ash JSON:API routes.

## Key Files

- `packages/server/lib/nixstasis/domain.ex`
- `packages/server/lib/nixstasis/devices/device.ex`
- `packages/server/lib/nixstasis/devices/pending_command.ex`
- `packages/server/lib/nixstasis/monitoring/alert.ex`
- `packages/server/lib/nixstasis/monitoring/alert_rule.ex`
- `packages/server/lib/nixstasis/monitoring/telemetry.ex`
- `packages/server/lib/nixstasis/reporting/custom_report.ex`
- `packages/server/lib/nixstasis/system_setting.ex`
- `packages/server/lib/nixstasis_web/ash_json_api_router.ex`
- `packages/server/priv/static/openapi.yaml`

## Public Interfaces

- Ash domain APIs defined in `Nixstasis.Domain`:
  - `list_devices`
  - `get_device`
  - `get_device_by_mac`
  - `create_device`
  - `register_device`
  - `update_device`
  - `destroy_device`
  - `list_pending_commands`
  - `create_pending_command`
  - `update_pending_command`
  - `destroy_pending_command`
  - `list_alerts`
  - `create_alert`
  - `update_alert`
  - `destroy_alert`
  - `list_rules`
  - `get_rule`
  - `create_rule`
  - `update_rule`
  - `destroy_rule`
  - `list_telemetry_events`
  - `create_telemetry_event`
  - `list_custom_reports`
  - `get_custom_report`
  - `create_custom_report`
  - `update_custom_report`
  - `destroy_custom_report`
  - `get_setting_by_key`
  - `create_setting`
  - `update_setting`

## Dependencies

### Internal

- Ash resources under `Nixstasis.Devices`, `Nixstasis.Monitoring`, `Nixstasis.Reporting`, and `Nixstasis.SystemSetting`.
- `NixstasisWeb.AshJsonApiRouter`.

### External

- Ash
- AshJsonApi
- AshPhoenix
- AshPostgres

## Client-Server Interaction Details

- Ash JSON:API routes are exposed under `/api/json`.
- Resource route groups:
  - `/api/json/devices`
  - `/api/json/pending_commands`
  - `/api/json/alerts`
  - `/api/json/alert_rules`
  - `/api/json/telemetry_events`
  - `/api/json/custom_reports`
  - `/api/json/system_settings`
- Swagger UI is forwarded at `/api/json/swaggerui`.

Traceable references:
- `packages/server/lib/nixstasis/domain.ex:1-122`
- `packages/server/lib/nixstasis_web/router.ex:22-28`
- `packages/server/priv/static/openapi.yaml:3190`
