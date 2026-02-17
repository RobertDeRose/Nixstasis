# Data Model: Report View Improvements

**Date**: 2026-02-15

## Entities

### CustomReport
- **Fields**:
  - `id` (integer)
  - `name` (string, unique case-insensitive)
  - `config` (map; includes `source`, `fields`, `filters`, and query-builder settings)
  - `inserted_at` (utc datetime)
  - `updated_at` (utc datetime)
- **Notes**: Existing persisted report definition entity reused for list and edit/delete flows.

### ReportListViewState
- **Fields**:
  - `sort_column` (`name` | `source` | `column_count` | `updated_at`)
  - `sort_direction` (`asc` | `desc`)
  - `column_filters` (map of column key to filter input)
  - `active_row_action` (`view` | `edit` | `delete` | nil)
- **Notes**: Transient LiveView state that determines what subset and ordering of reports is visible on the index page.

### ReportDeleteIntent
- **Fields**:
  - `report_id` (integer)
  - `report_name` (string)
  - `confirmation_status` (`idle` | `awaiting_confirmation` | `confirmed` | `cancelled`)
  - `requested_at` (utc datetime)
- **Notes**: Represents destructive-action state machine for explicit delete confirmation.

### ReportResultViewState
- **Fields**:
  - `report_id` (integer)
  - `sort_column` (string; must map to visible output column)
  - `sort_direction` (`asc` | `desc`)
  - `filters` (list of `ResultColumnFilter`)
  - `last_applied_at` (utc datetime)
- **Notes**: Transient state for sorting/filtering data shown on report detail page.

### ResultColumnFilter
- **Fields**:
  - `column_key` (string; visible report field alias/path)
  - `operator` (`gt` | `gte` | `eq` | `lte` | `lt`)
  - `raw_value` (string)
  - `coerced_type` (`number` | `string` | `datetime` | `boolean` | `unknown`)
  - `valid` (boolean)
  - `error_message` (string | nil)
- **Notes**: Encodes simple conditional filters for report results with strict operator set.

## Relationships

- One **CustomReport** has one mutable **ReportListViewState** per active user session.
- One **CustomReport** can have zero or one active **ReportDeleteIntent** at a time per active session.
- One **CustomReport** has one active **ReportResultViewState** per opened report detail session.
- One **ReportResultViewState** has many **ResultColumnFilter** entries.

## Validation Rules

- `CustomReport.name` must remain unique case-insensitively.
- `ReportListViewState.sort_column` must be one of allowed list columns.
- `ReportResultViewState.sort_column` must exist in the report's resolved visible fields.
- `ResultColumnFilter.operator` must be one of `gt`, `gte`, `eq`, `lte`, `lt`.
- Numeric comparisons (`gt`, `gte`, `lt`, `lte`) require successful numeric coercion when target field is numeric.
- Invalid filters must not crash rendering; they must produce recoverable validation feedback and keep previous valid state.

## State Transitions

### ReportDeleteIntent.confirmation_status
- `idle -> awaiting_confirmation` when user selects `Delete` action link.
- `awaiting_confirmation -> confirmed` when user confirms deletion.
- `awaiting_confirmation -> cancelled` when user dismisses/cancels modal.
- `confirmed -> idle` after deletion completes and row is removed from visible list.

### ReportResultViewState
- `initialized -> filtered` when any valid filter is applied.
- `initialized/filtered -> sorted` when sort is applied or changed.
- `sorted/filtered -> initialized` when user clears all sort/filter controls.
