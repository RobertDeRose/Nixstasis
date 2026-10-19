# Server Reporting

The `Nixstasis.Reporting` context: custom telemetry reports, their query execution, and saved table views.

## Owns

- `Nixstasis.Reporting` in `packages/server/lib/nixstasis/reporting.ex`, the `CustomReport` resource, and the table
  filters under `packages/server/lib/nixstasis/reporting/`.
- Saved report view preferences in the `report_view_preferences` table.

## Entry points

- `run_custom_report/3` builds and runs a report's telemetry query within a trusted device scope. The report detail
  LiveView and `GET /api/v1/reports/:id/results` both use it.
- `list_custom_reports_with_view/1` and `count_custom_reports_with_view/1` serve the report index with name and
  schema-field filters, deterministic sorting, and 50-row pagination applied in SQL.
- `create_custom_report/1`, `update_custom_report/2`, `delete_custom_report/1`, and `custom_report_name_taken?/1`
  manage reports for the `/reports` LiveViews.
- `save_view_preferences/3` and `load_view_preferences/2` persist an operator's table settings.
- Reports are also exposed as Ash JSON:API resources under `/api/json/custom_reports`.

## Boundaries

- **Device scope:** telemetry queries apply the operator's authorized device IDs in SQL before report filters,
  sorting, or pagination. The scope is passed separately, so caller options cannot override it. An unscoped operator
  sees the whole fleet; a scope with any malformed device ID returns no rows. The results endpoint requires a verified
  operator with report-view permission.
- **Schema identity:** reports and schema-aware builders identify a schema by `(product_name, schema_version)`. A
  report bound to one schema returns only matching devices; an all-schema report spans them. When devices with the same
  identity advertise conflicting definitions, the builder shows the conflict and blocks saving instead of choosing one.
  All-schema reports use a field type only when every contributing definition agrees, and otherwise fall back to string
  operators.
- **Result rows:** rows whose configured fields are all missing or empty are omitted, and a report with no valid field
  paths returns no rows.
- **Index payloads:** index rows carry identity, timestamps, a field count, and at most 25 truncated field labels; the
  full configuration loads only for detail and edit.
