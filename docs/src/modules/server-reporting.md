# Server Reporting

## Language

- Elixir.

## Runtime Context

- Server context, Ash resource layer, LiveView UI support.

## Purpose

- Manages custom report CRUD operations, report list/detail view data, table filtering/sorting, and session-scoped view preferences.

## Key Files

- `packages/server/lib/nixstasis/reporting.ex`
- `packages/server/lib/nixstasis/reporting/custom_report.ex`
- `packages/server/lib/nixstasis/reporting/query_builder.ex`
- `packages/server/lib/nixstasis/reporting/table_filters.ex`
- `packages/server/lib/nixstasis_web/live/reports/index_live.ex`
- `packages/server/lib/nixstasis_web/live/reports/show_live.ex`
- `packages/server/lib/nixstasis_web/live/reports/form_component.ex`

## Public Interfaces

- `Nixstasis.Reporting.list_custom_reports/0`
- `Nixstasis.Reporting.list_custom_reports_with_view/1`
- `Nixstasis.Reporting.get_custom_report!/1`
- `Nixstasis.Reporting.create_custom_report/1`
- `Nixstasis.Reporting.custom_report_name_taken?/1`
- `Nixstasis.Reporting.update_custom_report/2`
- `Nixstasis.Reporting.delete_custom_report/1`
- `Nixstasis.Reporting.save_view_preferences/3`
- `Nixstasis.Reporting.load_view_preferences/2`
- `Nixstasis.Reporting.change_custom_report/2`

## Dependencies

### Internal

- `Nixstasis.Domain`
- `Nixstasis.Repo`
- `Nixstasis.Reporting.CustomReport`
- `Nixstasis.Reporting.TableFilters`

### External

- Ecto.Query
- AshPhoenix
- Postgres-backed `report_view_preferences` table for persisted view preferences

## Client-Server Interaction Details

- Reporting is primarily used by browser LiveView routes under `/reports`.
- Reports with a selected schema identity limit telemetry results to matching
  product/version devices; all-schema reports retain cross-schema results.
- Telemetry report results omit rows where every configured payload field is
  missing or empty; rows with at least one configured value remain visible.
- Custom reports are also exposed through Ash JSON:API under `/api/json/custom_reports`.
- `GET /api/v1/reports/:id/results` remains a bespoke controller endpoint for
  now because it executes report query construction and returns shaped preview
  rows, not simple `CustomReport` CRUD.
- Report list/detail interaction requirements, including filtering, sorting,
  delete confirmation, and saved view preferences, are captured in
  [Report View Improvements](../features/report-view-improvements/index.md).
- Schema-aware alert/report builder option lookup and invalid-selection clearing
  uses `(product_name, schema_version)` as the canonical schema identity. If
  matching devices advertise divergent definitions, the report builder exposes a
  conflict message and blocks save rather than selecting one device arbitrarily.
  Missing, invalid, or otherwise unavailable schema definitions show a blocking
  recovery message and keep Save disabled until a valid schema scope is available.
  All-schema and all-version reports use a field type only when contributing
  definitions agree; disagreements fall back to generic string operators rather
  than selecting a version arbitrarily. Multi-schema option loading uses one
  bounded database batch that returns one canonical definition per identity,
  instead of issuing one full schema lookup per reference.

Traceable references:

- `packages/server/lib/nixstasis/reporting.ex:1-200`
- `packages/server/lib/nixstasis/domain.ex:52-58`
- `packages/server/lib/nixstasis_web/router.ex:41-44`
