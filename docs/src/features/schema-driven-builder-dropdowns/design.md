<!-- workflow-migration:legacy-markdown-to-beads -->

# Schema-Driven Builder Dropdowns

## Feature Name

`schema-driven-builder-dropdowns`

## Goal

Generate alert and report builder dropdown options from available schemas so users
select valid fields instead of typing fragile field names manually.

## Users

- Users creating alert rules.
- Users building custom reports.

## Requirements

- Generate alert builder options from the explicitly selected schema version.
- Generate report builder options from the explicitly selected schema version.
- Keep alert and report schema selections independent.
- Refresh dropdown options when schema context changes.
- Clear invalidated selections and show inline reselect-required feedback.
- Block save when current selections do not match the active schema.
- Treat `(product_name, schema_version)` as the canonical schema identity. If
  matching devices advertise divergent definitions, mark the schema unavailable
  and block dependent saves instead of selecting an arbitrary definition.
- Provide clear empty, missing, unreadable, conflicting, and unauthorized states.
- Disambiguate duplicate display labels while preserving selectability.
- Load typical schema option sets within 2 seconds.
- Expose schema reference/options and builder validation endpoints where needed by the UI.

## Proposed Design

Server-side schema option services normalize schema metadata into UI options,
validate selected slots against the active schema, and return cleared slot IDs
when selections become invalid. A `(product_name, schema_version)` pair is one
canonical schema identity; the service detects divergent definitions for that
pair and fails closed with a visible unavailable/conflicting-schema state. Alert
and report builders consume the service without sharing mutable schema-selection
state.

## Validation

- Builder dropdowns populate from selected schemas.
- Switching schemas clears invalid prior selections and preserves valid ones.
- Missing schema data disables affected controls and explains recovery steps.
- Conflicting definitions for one schema identity disable affected controls and
  explain that the schema must be reconciled before use.
- Authorization loss blocks save until access returns.

## Metadata

- Beads feature root: `nixstasis-yju`
- Feature slug: `schema-driven-builder-dropdowns`
- Base branch: `dev`
- Status: in progress

## Feature Summary

Populate alert and report builder fields from explicit schema versions and validate selections against the active schema
instead of accepting fragile free-form field names.

## User Intent

Rule and report authors need discoverable valid fields, independent builder state, and clear recovery when a schema
change invalidates prior selections.

## Goals

Make valid schema fields discoverable, keep alert and report state independent, and prevent stale selections from save.

## User-Facing Behavior

Schema selection refreshes dropdowns, preserves still-valid values, clears invalid values with inline guidance, blocks
unsafe saves, and presents empty, unavailable, conflicting, unauthorized, and duplicate-label states.

## Non-Goals

The feature does not merge alert and report builder state, infer a schema version silently, or permit stale selections
for compatibility.

## Existing Context

Ash-backed builder actions, generated OpenAPI, alert and report LiveViews, schema normalization, and permission helpers
provide the current implementation foundation.

## Architecture Consistency

Server schema-option and validation services own normalization and validity. Each LiveView owns its independent selected
schema and form state; generated contracts expose the reusable actions. Generated builder actions use the existing
report-view authorization boundary; this feature does not introduce per-device schema ACLs. Within that boundary, schema
identity is canonical by `(product_name, schema_version)` and divergent definitions fail closed rather than being merged
or chosen arbitrarily.

## Operational Considerations

Option loading must remain bounded and authorization-aware. The service must inspect one canonical schema identity per
explicit-scope request, and all-schema or all-version report mode must use one bounded/batched database lookup that returns
one canonical definition per requested identity rather than an unbounded full-schema request per reference. LiveView assigns
should retain the normalized option list and derive display maps/lists as needed instead of retaining duplicate collections.
Missing, unreadable, or conflicting schema state fails visibly without retaining invalid saved configuration. The HTTP
compatibility wrapper records measured lookup time; the shared domain payload does not claim a synthetic performance value.
The shared option service also emits the measured
`[:nixstasis, :builder, :schema_options, :load]` event with `duration_ms` and
result metadata for bounded performance verification; it does not place that
measurement in the shared payload.

## Documentation Impact

Update builder contracts in `docs/src/client-server-interface.md`, generated OpenAPI references,
`docs/src/modules/server-monitoring.md`, `docs/src/modules/server-reporting.md`, and `docs/src/modules/server-web.md`.
Record schema-action/OpenAPI regeneration and validation guidance in
`docs/src/development/tooling.md`; keep `docs/src/reference/openapi/builder-api.yaml` aligned with the retained
compatibility wrapper.

## Validation Strategy

Run normalizer, validator, JSON:API, controller compatibility, alert LiveView, report LiveView, authorization, conflict
handling, and performance checks. Verify the two-second option-load target with bounded fixture sizes. Capture the
90-second task-flow evidence only in a valid operator observation window; otherwise record the measurement as deferred
without claiming a usability pass/fail.

### Report task-flow measurement record — 2026-08-05

- Scenario: create a report, select a schema, choose a column, add a typed filter, and save it.
- Participant/sample: no valid operator observation window was available for this implementation run.
- Elapsed time and pass/fail: not recorded; the 90-second target is deferred rather than evaluated.
- Limitation: automated LiveView/browser checks and synthetic timings are implementation evidence, not human-usability
  evidence. A future observation must record participant/sample details, procedure, elapsed time, and limitations before
  claiming a usability result.

### Alert task-flow measurement record — 2026-08-05

- Scenario: open the alert rule builder, select a schema/version, choose a condition field, set an operator and
  threshold, and save the rule.
- Participant/sample: no valid operator observation window was available for this implementation run.
- Elapsed time and pass/fail: not recorded; the 90-second target is deferred rather than evaluated.
- Limitation: automated LiveView/browser checks and synthetic timings are implementation evidence, not human-usability
  evidence. A future observation must record participant/sample details, procedure, elapsed time, and limitations before
  claiming a usability result.

### Verification record — 2026-08-05

- `NIXSTASIS_DB_AUTOSTART=false mise x -- mix test test/nixstasis/schema_options_test.exs test/nixstasis/schema_options/builder_contract_test.exs test/nixstasis_web/controllers/builder_schema_controller_test.exs test/nixstasis_web/live/alerts_live_test.exs test/nixstasis_web/live/reports_live_test.exs`: 98 tests, 0 failures.
- `NIXSTASIS_DB_AUTOSTART=false mise x -- mix precommit`: 627 tests, 0 failures; compile, dependency, format, and test checks passed.
- `NIXSTASIS_DB_AUTOSTART=false mise x -- mix ash.codegen --check`: passed; no Ash codegen drift.
- `uv run scripts/check-docs.py`: passed. `mise run check`: passed, including server compile/format, Go checks, docs build, and repository linters.
- Covered behavior includes canonical option loading, divergent-schema conflict blocking, selection invalidation, degraded empty/unavailable states, compatibility errors, and existing authorization regression coverage.
- Limitations: LiveView test output contains pre-existing missing-form-ID warnings, and mdBook lint reports pre-existing warnings; neither produced a failing check. No browser automation or human-usability claim was substituted for operator observation.

### Performance verification record — 2026-08-05

- Alert and report LiveView timing assertions emitted actual monotonic `duration_ms` telemetry and passed the 2,000 ms bound in 95 focused tests with 0 failures.
- `NIXSTASIS_DB_AUTOSTART=false mise x -- mix precommit` passed after instrumentation with 629 tests and 0 failures.
- The assertion measures option-service execution only; it is not a human task-completion measurement and does not alter the shared `load_time_ms` payload.

## Implementation Decomposition

Beads retains performance and close-out evidence. The migrated implementation children `.7.1` through `.7.34` and
`.7.36` cover the already-delivered option, validation, alert/report integration, and contract slices. Remaining
implementation work is the canonical schema identity/conflict boundary and its regression coverage; migrated `.7.35`,
`.7.37`, `.7.38`, and `.7.39` own performance, verification, and operator-observation evidence. Do not duplicate those
migrated task boundaries with parallel implementation beads.

## Dependencies and Parallelism

Normalization and action contract tests can proceed independently from alert and report UI tests. Performance
measurements depend on the integrated builders.

## Risks and Tradeoffs

Strict invalidation prevents stale configuration but can interrupt editing; explicit feedback and preservation of valid
slots balance safety and usability.

## Rejected Alternatives

Free-form field entry, shared mutable alert/report schema state, silent fallback to another schema version, arbitrary
first-device selection for a canonical schema identity, and union/intersection of divergent definitions remain rejected.

## Open Questions

Performance and task-completion measurements remain open.

## Deferred Decisions

Cross-product schema composition, per-device schema ACLs, and broader builder redesign remain outside the current
feature. The existing builder contract uses the report-view authorization boundary; changing that boundary requires a
separate design.
