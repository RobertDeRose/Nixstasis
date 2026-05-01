# Quickstart: Report View Improvements

## Goal

Validate Custom Reports list sorting/filtering, explicit `View/Edit/Delete` row actions, delete confirmation, query-modal editing, and report-results sorting/filtering with operators `>`, `>=`, `==`, `<=`, `<`.

## Prerequisites

- Run from repo root: `.`
- Server dependencies installed for `packages/server`
- At least three custom reports with varied names, sources, and column counts
- At least one report with numeric result columns (for comparator checks)

## 1) Run automated test suite for reports flows

```bash
cd packages/server
mix test test/nixstasis_web/live/reports_live_test.exs
```

Expected:
- Existing and new report LiveView tests pass.
- Coverage includes list sorting/filtering, edit modal preload/save, and delete confirmation behavior.

## 2) Verify Custom Reports list action links

1. Open `/reports`.
2. Inspect a populated row.

Expected:
- Row displays clearly styled `View`, `Edit`, and `Delete` action links.
- `Delete` has distinct destructive affordance.
- Focus states are keyboard-accessible and visible.

## 3) Verify Custom Reports list sorting and filtering

1. Sort by `Name` ascending then descending.
2. Sort by `Source` and `Columns`.
3. Apply a column filter (for example, `Name` contains a known substring).

Expected:
- Rows reorder deterministically for each sort change.
- Filter reduces rows to only matching entries.
- Clearing filter restores the full list without page reload errors.

## 4) Verify Edit action uses existing query modal

1. Click `Edit` on a report row.
2. Confirm modal opens with current report query configuration.
3. Modify query fields/filters and save.

Expected:
- Modal is pre-populated with report's existing query data.
- Save updates the report and returns user to updated list state.

## 5) Verify Delete action confirmation

1. Click `Delete` on a report row.
2. Cancel confirmation once.
3. Re-open confirmation and confirm deletion.

Expected:
- Cancel leaves report unchanged.
- Confirm removes report from list and shows success feedback.
- No deletion occurs without explicit confirmation.

## 6) Verify report detail sorting and filter operators

1. Click `View` for a report with multiple result columns.
2. Sort results by at least two different columns.
3. Apply per-column filters using `>`, `>=`, `==`, `<=`, `<`.

Expected:
- Sorting updates row order correctly for selected column/direction.
- Each operator returns the expected subset of rows.
- Invalid comparator/value combinations show recoverable validation feedback.

## 7) Interaction performance check

Measure from sort/filter action to updated rendered rows on list and detail views.

Expected:
- 95% of interactions complete in <=1 second for typical datasets.

## 8) Regression checks

1. Create a new report from `/reports/new`.
2. Ensure report view still renders with no filters applied.
3. Verify E2E-internal reports remain excluded from normal custom-report flow.

Expected:
- Existing report creation and baseline viewing behavior remains intact.
- New interactions do not regress existing report restrictions.

## 9) SC-002 baseline capture (pre-change median review time)

- Capture timestamped median review-time baseline before release validation.
- Baseline method:
  1. Run 10 representative report-review flows (open report, apply sort, apply filter, identify target value).
  2. Record each duration in seconds.
  3. Compute median and store below.

### Baseline Record

- Capture date: 2026-02-15
- Baseline sample size: 10 runs
- Baseline median review time: _TO BE RECORDED DURING RELEASE VALIDATION_

## 10) SC-004 support ticket baseline and comparison

- Define report-view support tags: `report-view-sort`, `report-view-filter`, `report-view-actions`.
- Baseline window: 30 days before release date.
- Post-release window: days 1-30 after release.

### Baseline Record

- Capture date: 2026-02-15
- Baseline ticket count (30 days): _TO BE RECORDED DURING RELEASE VALIDATION_
- Comparison query owner: release manager / support lead

## 11) Validation run log

- 2026-02-15: Automated suite executed for report LiveView and reporting context updates.
- Command: `mix test test/nixstasis/reporting/table_filters_test.exs test/nixstasis/reporting/custom_report_list_test.exs test/nixstasis/reporting/query_builder_test.exs test/nixstasis_web/live/reports_live_test.exs`
- Result: PASS (38 tests, 0 failures)
