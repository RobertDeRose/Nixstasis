# Research: Report View Improvements

**Date**: 2026-02-15
**Spec**: `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/010-report-view-improvements/spec.md`

## Decisions

### 1) Report List Row Actions
- **Decision**: Add three explicit action links per row on Custom Reports index: `View`, `Edit`, `Delete`.
- **Rationale**: Keeps primary operations visible in-context and avoids hidden affordances for common report maintenance tasks.
- **Alternatives considered**: Single kebab menu for all actions; icon-only actions without text labels.

### 2) Edit Flow Reuse
- **Decision**: Use the existing report query modal flow for editing, pre-populated with the selected report configuration.
- **Rationale**: Reuses validated query-builder behavior and minimizes mental model changes for users.
- **Alternatives considered**: Dedicated edit page; inline row edit mode in table.

### 3) Delete Confirmation Pattern
- **Decision**: Deleting from list requires an explicit confirmation modal before the destroy action is executed.
- **Rationale**: Prevents accidental destructive actions and aligns with established safety expectations for irreversible operations.
- **Alternatives considered**: Immediate delete with flash undo; browser-native confirm dialog.

### 4) Sorting/Filtering in Custom Reports List
- **Decision**: Enable per-column sort and simple per-column filter controls on index list state managed by LiveView assigns and server-side query constraints.
- **Rationale**: Server-side shaping scales better with report counts and keeps behavior deterministic across reloads.
- **Alternatives considered**: Client-only sorting/filtering of rendered rows; global full-text search only.

### 5) Sorting/Filtering in Report Results
- **Decision**: Support sortable columns and per-column filter conditions with operators strictly limited to `>`, `>=`, `==`, `<=`, `<`.
- **Rationale**: Matches explicit user requirement while constraining operator surface for reliable typed comparisons.
- **Alternatives considered**: Add `!=`/`contains`; freeform SQL-like expression input.

### 6) Type Coercion for Comparisons
- **Decision**: Apply comparator logic using column data type metadata where available, with safe fallback to lexicographic comparison for non-numeric content.
- **Rationale**: Prevents incorrect numeric ordering/filtering while preserving predictable behavior on mixed datasets.
- **Alternatives considered**: Treat all values as strings; reject non-numeric comparisons entirely.

### 7) Visual Treatment of Action Links
- **Decision**: Style `View`, `Edit`, and `Delete` as clear action links with distinct semantic emphasis (`Delete` danger style), while preserving accessibility contrast/focus states.
- **Rationale**: Improves discoverability and reduces accidental action confusion.
- **Alternatives considered**: Uniform neutral button styles; contextual row-hover actions only.
