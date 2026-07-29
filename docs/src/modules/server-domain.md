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
- `packages/server/lib/nixstasis/command_allowlists/command_entry.ex`
- `packages/server/lib/nixstasis/command_allowlists/command_entry_version.ex`
- `packages/server/lib/nixstasis/command_allowlists/category.ex`
- `packages/server/lib/nixstasis/command_allowlists/command_entry_category.ex`
- `packages/server/lib/nixstasis/command_allowlists/device_policy_assignment.ex`
- `packages/server/lib/nixstasis/command_allowlists/device_policy_assignment_source.ex`
- `packages/server/lib/nixstasis/command_allowlists/policy_delivery_result.ex`
- `packages/server/lib/nixstasis/command_allowlists.ex`
- `packages/server/lib/nixstasis/command_allowlists/policy_resolver.ex`
- `packages/server/lib/nixstasis/command_catalog/category.ex`
- `packages/server/lib/nixstasis/command_catalog/catalog_command.ex`
- `packages/server/lib/nixstasis/command_catalog/package_mapping.ex`
- `packages/server/lib/nixstasis/command_catalog/device_inventory_snapshot.ex`
- `packages/server/lib/nixstasis/command_catalog/resolver.ex`
- `packages/server/lib/nixstasis_web/ash_json_api_router.ex`
- `packages/server/priv/static/openapi.yaml`

## Public Interfaces

- Command allowlist entries validate lowercase command names and absolute command paths without whitespace or shell metacharacters at the resource and database layers.
- `Nixstasis.Domain.preview_command_policy/1` resolves selected command entries and category tags into a preview containing commands, provenance, conflicts, diff, and the raw v1 payload body.
- The server-curated command catalog stores catalog categories, approved command records, OS-family package mappings, and the latest untrusted device command inventory snapshot.
- `Nixstasis.Domain.command_inventory_probe_manifest/0` returns a non-authoritative `catalog-v1` probe manifest containing package names and command probes from active catalog mappings.
- `Nixstasis.Domain.preview_catalog_command_compatibility/1` resolves selected catalog commands against selected devices and returns per-device statuses: `stale_inventory`, `unsupported_os`, `supported`, `missing_package`, `conflict`, `package_installed`, and `command_path_resolved`.
- Inventory is current only when its probe catalog version matches the active catalog version and its `observed_at` timestamp is within the existing `offline_window` setting.
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
  - `list_command_allowlist_entries`
  - `get_command_allowlist_entry`
  - `create_command_allowlist_entry`
  - `update_command_allowlist_entry`
  - `list_command_allowlist_entry_versions`
  - `create_command_allowlist_entry_version`
  - `list_command_allowlist_categories`
  - `get_command_allowlist_category`
  - `create_command_allowlist_category`
  - `update_command_allowlist_category`
  - `destroy_command_allowlist_category`
  - `list_command_allowlist_entry_categories`
  - `create_command_allowlist_entry_category`
  - `destroy_command_allowlist_entry_category`
  - `list_command_policy_assignments`
  - `get_command_policy_assignment`
  - `create_command_policy_assignment`
  - `list_command_policy_assignment_sources`
  - `create_command_policy_assignment_source`
  - `list_command_policy_delivery_results`
  - `create_command_policy_delivery_result`
  - `preview_command_policy`
  - `list_command_catalog_categories`
  - `get_command_catalog_category`
  - `create_command_catalog_category`
  - `update_command_catalog_category`
  - `destroy_command_catalog_category`
  - `list_command_catalog_commands`
  - `get_command_catalog_command`
  - `create_command_catalog_command`
  - `update_command_catalog_command`
  - `list_command_catalog_mappings`
  - `get_command_catalog_mapping`
  - `create_command_catalog_mapping`
  - `update_command_catalog_mapping`
  - `destroy_command_catalog_mapping`
  - `list_device_command_inventory_snapshots`
  - `get_device_command_inventory_snapshot`
  - `create_device_command_inventory_snapshot`
  - `update_device_command_inventory_snapshot`
  - `destroy_device_command_inventory_snapshot`
  - `command_inventory_probe_manifest`
  - `preview_catalog_command_compatibility`

## Dependencies

### Internal

- Ash resources under `Nixstasis.Devices`, `Nixstasis.Monitoring`, `Nixstasis.Reporting`, `Nixstasis.CommandAllowlists`, and `Nixstasis.SystemSetting`.
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
