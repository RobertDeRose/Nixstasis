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
request, and all-schema report mode must use a bounded/batched lookup rather than an unbounded request per reference.
Missing, unreadable, or conflicting schema state fails visibly without retaining invalid saved configuration. The HTTP
compatibility wrapper records measured lookup time; the shared domain payload does not claim a synthetic performance value.

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
