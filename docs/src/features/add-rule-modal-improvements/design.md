# Add Rule Modal Improvements

## Feature Name

`add-rule-modal-improvements`

## Goal

Bring Add Rule modal behavior to parity with the Create Report modal for layout,
validation, keyboard interaction, and accessible feedback.

## Users

- Users creating or editing alert rules.
- Keyboard-only and accessibility-focused users.

## Requirements

- Match Create Report modal structure, action placement, validation placement, and close affordances.
- Use one primary save action and a clear cancel path.
- Tie save availability to validation state.
- Focus the first actionable rule-building control on open.
- Keep focus order logical, visible, and contained while modal is open.
- Support `Ctrl+Enter` / `Cmd+Enter` to save.
- Do not let plain Enter in text fields force modal submission.
- Confirm close/cancel only when unsaved changes exist.
- In edit mode, keep only rule name immutable.
- Success feedback auto-dismisses; error feedback persists until user action or correction.
- Meet WCAG 2.1 AA expectations for modal dialogs and form validation feedback.

## Proposed Design

The feature refines the existing alert rule LiveViews and modal component state.
It focuses on interaction quality and validation recovery rather than changing
alert-rule semantics.

## Validation

- Keyboard-only users can complete create/edit flows.
- Invalid inputs show inline guidance and preserve entered values.
- Duplicate/rapid submits process only one save.
- Unsaved changes prompt before close; unchanged modals close immediately.
