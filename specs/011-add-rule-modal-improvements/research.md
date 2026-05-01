# Research: Add Rule Modal Improvements

**Date**: 2026-02-16
**Spec**: `specs/011-add-rule-modal-improvements/spec.md`

## Decisions

### 1) Edit-mode immutability scope
- **Decision**: In edit mode, only rule name is immutable.
- **Rationale**: This mirrors the Create Report pattern and protects identifier stability while preserving flexibility to correct conditions/operators/threshold.
- **Alternatives considered**: Locking more identifying fields; allowing full mutability for all fields.

### 2) Keyboard submit behavior
- **Decision**: Support `Ctrl+Enter` / `Cmd+Enter` as explicit save shortcut; plain Enter in text-entry contexts does not force full modal submit.
- **Rationale**: Reduces accidental submits while still enabling fast keyboard-driven save.
- **Alternatives considered**: Plain Enter submits globally; no keyboard shortcut.

### 3) Cancel/Escape with unsaved changes
- **Decision**: Show confirmation prompt only when unsaved changes exist.
- **Rationale**: Prevents accidental data loss while avoiding unnecessary prompts for pristine forms.
- **Alternatives considered**: Always close immediately; always prompt; auto-save drafts.

### 4) Accessibility target
- **Decision**: Treat modal interactions and form feedback as WCAG 2.1 AA expectations baseline.
- **Rationale**: Provides a measurable, accepted quality target and aligns with keyboard/focus/error-feedback requirements.
- **Alternatives considered**: Internal checklist only; no explicit target beyond current behavior.

### 5) Save outcome messaging
- **Decision**: Success feedback auto-dismisses; error feedback persists until explicit user dismissal or corrective action.
- **Rationale**: Keeps happy path lightweight and ensures error conditions remain actionable and visible.
- **Alternatives considered**: Auto-dismiss both; persist both; external-only notifications.

### 6) Implementation location and reuse strategy
- **Decision**: Keep implementation in existing `AlertLive.Index` Add Rule modal flow and reuse established modal/key interaction patterns from report modal where applicable.
- **Rationale**: Minimizes architecture churn and keeps behavior consistent with existing app interaction model.
- **Alternatives considered**: Introduce new LiveComponent for Add Rule immediately; add a separate alert-rules creation surface.
