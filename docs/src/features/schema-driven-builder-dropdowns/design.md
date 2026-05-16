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
