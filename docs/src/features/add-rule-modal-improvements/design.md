<!-- workflow-migration:legacy-markdown-to-beads -->

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

## Metadata

- Beads feature root: `nixstasis-inh`
- Feature slug: `add-rule-modal-improvements`
- Base branch: `dev`
- Status: in progress

## Feature Summary

Bring alert-rule create and edit modal interactions to the established report-modal quality, validation, keyboard, and
accessibility patterns.

## User Intent

Alert authors need predictable save and cancellation behavior, preserved input after validation failures, and complete
keyboard access without accidental submission.

## Goals

Deliver report-modal parity, accessible keyboard behavior, validation recovery, and measured first-attempt usability.

## User-Facing Behavior

The modal provides one primary save action, inline persistent errors, auto-dismissed success, focus placement and
containment, command-enter save, safe plain-enter behavior, and dirty-close confirmation.

## Non-Goals

The feature does not change alert-rule semantics, evaluation, notification delivery, or the broader alert information
architecture.

## Existing Context

Existing alert LiveViews, modal components, report-modal interaction patterns, and alert validation remain the implementation
foundation.

## Architecture Consistency

LiveView owns modal state and validation recovery; shared components own dialog semantics and focus-visible styling; the
existing monitoring context remains the rule authority.

## Operational Considerations

Duplicate and rapid submissions must remain idempotent. Validation failures preserve input and enough state for support
diagnosis without logging sensitive operator data.

## Documentation Impact

Update `docs/src/modules/server-monitoring.md` and server-web interaction guidance if externally visible behavior or
keyboard contracts change.

## Validation Strategy

Run alert LiveView tests for create, edit, validation, focus order, keyboard shortcuts, duplicate submits, dirty close,
and feedback persistence, then complete the outstanding measured success-criteria tasks.

## Implementation Decomposition

Beads retains the remaining baseline and timed usability measurements. Implementation slices cover modal parity,
validation recovery, keyboard behavior, dirty state, and feedback lifecycle.

## Dependencies and Parallelism

Component accessibility and alert validation tests can proceed independently; measured flow checks depend on the final
integrated modal.

## Risks and Tradeoffs

Aggressive keyboard shortcuts can cause accidental saves, while overusing confirmation adds friction. Dirty-state and
validation logic must remain synchronized with LiveView changesets.

## Rejected Alternatives

Plain-enter submission, unconditional close confirmation, and divergent report and alert modal conventions remain
rejected.

## Open Questions

Only the outstanding measured success criteria remain open; no unresolved product policy is recorded.

## Deferred Decisions

Broader alert-builder redesign is outside this focused interaction-quality feature.
