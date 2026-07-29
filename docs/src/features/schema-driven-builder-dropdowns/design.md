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
- Provide clear empty, missing, unreadable, and unauthorized states.
- Disambiguate duplicate display labels while preserving selectability.
- Load typical schema option sets within 2 seconds.
- Expose schema reference/options and builder validation endpoints where needed by the UI.

## Proposed Design

Server-side schema option services normalize schema metadata into UI options,
validate selected slots against the active schema, and return cleared slot IDs
when selections become invalid. Alert and report builders consume the service
without sharing mutable schema-selection state.

## Validation

- Builder dropdowns populate from selected schemas.
- Switching schemas clears invalid prior selections and preserves valid ones.
- Missing schema data disables affected controls and explains recovery steps.
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
unsafe saves, and presents empty, unavailable, unauthorized, and duplicate-label states.

## Non-Goals

The feature does not merge alert and report builder state, infer a schema version silently, or permit stale selections
for compatibility.

## Existing Context

Ash-backed builder actions, generated OpenAPI, alert and report LiveViews, schema normalization, and permission helpers
provide the current implementation foundation.

## Architecture Consistency

Server schema-option and validation services own normalization and validity. Each LiveView owns its independent selected
schema and form state; generated contracts expose the reusable actions.

## Operational Considerations

Option loading must remain bounded and authorization-aware. Missing or unreadable schema state fails visibly without
retaining invalid saved configuration.

## Documentation Impact

Update builder contracts in `docs/src/client-server-interface.md`, generated OpenAPI references, server monitoring and
reporting module pages, and developer guidance for schema action changes.

## Validation Strategy

Run normalizer, validator, JSON:API, controller compatibility, alert LiveView, report LiveView, authorization, and
performance checks. Complete the outstanding two-second load and 90-second task-flow measurements.

## Implementation Decomposition

Beads retains performance and close-out evidence. Implemented slices include schema actions, option normalization,
selection clearing, save validation, independent builder state, and generated contract coverage.

## Dependencies and Parallelism

Normalization and action contract tests can proceed independently from alert and report UI tests. Performance
measurements depend on the integrated builders.

## Risks and Tradeoffs

Strict invalidation prevents stale configuration but can interrupt editing; explicit feedback and preservation of valid
slots balance safety and usability.

## Rejected Alternatives

Free-form field entry, shared mutable alert/report schema state, and silent fallback to another schema version remain
rejected.

## Open Questions

Only performance and task-completion measurements remain open.

## Deferred Decisions

Cross-product schema composition and broader builder redesign remain outside the current feature.
