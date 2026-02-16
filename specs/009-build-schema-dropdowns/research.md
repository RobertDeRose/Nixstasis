# Research: Schema-Driven Builder Dropdowns

**Date**: 2026-02-14
**Spec**: `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/009-build-schema-dropdowns/spec.md`

## Decisions

### 1) Schema Version Ownership per Builder
- **Decision**: Alert and report builders each use their own explicitly selected schema version.
- **Rationale**: Prevents cross-builder coupling and preserves predictable behavior when both builders are used in the same user session.
- **Alternatives considered**: Single workspace-wide schema version; always latest schema version.

### 2) Invalid Selection Handling on Schema Change
- **Decision**: Automatically clear selections no longer valid for the newly active schema and display inline "reselect required" feedback.
- **Rationale**: Prevents accidental persistence of invalid config while reducing user correction effort and confusion.
- **Alternatives considered**: Keep invalid values and block save only; automatic remap by field-name similarity.

### 3) Permission-Loss Behavior
- **Decision**: Fail closed when schema access is lost during editing: clear schema-derived options, block save, and show authorization messaging.
- **Rationale**: Safer authorization posture and avoids exposing stale unauthorized field options.
- **Alternatives considered**: Keep cached options temporarily; allow save with warning.

### 4) Shared Option Normalization Strategy
- **Decision**: Use a single shared schema option normalization layer consumed by both builders.
- **Rationale**: Guarantees consistent option labels/order and centralizes validation logic required by FR-007.
- **Alternatives considered**: Duplicate option mapping logic in each LiveView component.

### 5) Performance Measurement Boundary
- **Decision**: Measure dropdown readiness from schema selection event to first render with populated options.
- **Rationale**: Matches user-perceived responsiveness and aligns directly with SC-006.
- **Alternatives considered**: Measure backend-only query time; measure total form-save cycle.
