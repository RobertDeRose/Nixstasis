# Data Model: Add Rule Modal Improvements

**Date**: 2026-02-16

## Entities

### AlertRule
- **Purpose**: Persisted alert rule definition that drives runtime alert generation.
- **Fields**:
  - `id` (integer)
  - `name` (string; immutable in edit context for this feature)
  - `product_name` (string)
  - `condition_field` (string)
  - `operator` (enum-like string from allowed rule operators)
  - `threshold_value` (string)
  - `inserted_at` (utc datetime)
  - `updated_at` (utc datetime)
- **Relationships**: Linked logically to schema/product context for field validation.

### AlertRuleDraftState
- **Purpose**: In-modal transient state for create/edit form interaction.
- **Fields**:
  - `mode` (`create` | `edit`)
  - `is_dirty` (boolean)
  - `selected_schema_id` (string | nil)
  - `selected_schema_version` (string | nil)
  - `condition_field` (string)
  - `operator` (string)
  - `threshold_value` (string)
  - `validation_issues` (list of `ValidationIssue`)
  - `save_enabled` (boolean)
- **Relationships**: Mirrors editable subset of `AlertRule` plus UI-only state.

### ValidationIssue
- **Purpose**: User-facing validation or compatibility issue in modal flow.
- **Fields**:
  - `field_key` (string)
  - `message` (string)
  - `severity` (`error` | `warning`)
  - `blocking` (boolean)
- **Relationships**: Attached to `AlertRuleDraftState`; blocks save when `blocking=true`.

### SaveOutcomeFeedback
- **Purpose**: Represents post-submit status behavior.
- **Fields**:
  - `type` (`success` | `error`)
  - `message` (string)
  - `dismiss_mode` (`auto` | `manual_or_corrective_action`)
  - `visible` (boolean)
- **Relationships**: Derived from create/update submission result.

### UnsavedChangeDecision
- **Purpose**: Confirmation state when cancel/Escape is triggered while dirty.
- **Fields**:
  - `trigger` (`escape` | `cancel_click`)
  - `decision` (`pending` | `discard` | `resume_editing`)
- **Relationships**: Applies only when `AlertRuleDraftState.is_dirty=true`.

## Validation Rules

- Rule name is required for creation and immutable in edit mode.
- `condition_field` must be valid for the currently selected schema scope.
- `operator` must be within allowed alert-rule operator set.
- `threshold_value` must satisfy existing operator/type validation expectations.
- Save remains disabled while blocking `ValidationIssue` entries exist.

## State Transitions

### Draft lifecycle
- `initialized -> dirty` when any editable value changes.
- `dirty -> confirmed_discard` when user confirms close on unsaved changes.
- `dirty -> saved` when valid submit succeeds.
- `dirty -> validation_error` when submit fails validation.

### Save feedback lifecycle
- `none -> success(auto)` on successful save.
- `none -> error(manual_or_corrective_action)` on failed save.
- `error -> hidden` when user dismisses message or resolves conditions that clear the error.

### Cancel/Escape behavior
- `pristine + cancel/escape -> close`
- `dirty + cancel/escape -> confirmation_required`
- `confirmation_required + discard -> close`
- `confirmation_required + resume_editing -> modal_stays_open`
