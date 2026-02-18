# Quickstart: Add Rule Modal Improvements

## Goal

Validate that Add Rule modal behavior matches Create Report modal quality for structure, focus, keyboard handling, validation feedback, dirty-state cancel handling, and create/edit consistency.

## Prerequisites

- Repo root: `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis`
- Phoenix app dependencies installed under `packages/server`
- At least one schema-enabled device available for alert field selection
- Existing alert rule present for edit-mode checks

## 1) Run automated tests for alert/report modal interaction coverage

```bash
cd /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server
mix test test/nixstasis_web/live/alerts_live_test.exs test/nixstasis_web/live/reports_live_test.exs
```

Expected:
- All tests pass.
- Coverage confirms no regressions in report modal parity behavior used as reference.

## 2) Validate Add Rule modal baseline structure parity

1. Open `/alerts/new`.
2. Compare section layout and action placement against `/reports/new` modal behavior patterns.

Expected:
- Add Rule uses equivalent structure conventions (clear sections, predictable primary action placement, validation/error display location).

## 3) Validate focus behavior on modal open

1. Open Add Rule modal.
2. Observe initial focus target.

Expected:
- Focus lands on the first actionable rule-building control (not inert content).

## 4) Validate keyboard interaction semantics

1. Navigate modal using keyboard only.
2. Use `Ctrl+Enter` (or `Cmd+Enter` on macOS) to submit when valid.
3. Press Enter while typing in text-entry contexts.

Expected:
- Keyboard navigation remains trapped within modal with visible focus.
- `Ctrl/Cmd+Enter` submits when form is valid.
- Plain Enter in text-entry contexts does not force full modal submit.

## 5) Validate dirty-state cancel/Escape behavior

1. Open Add Rule and modify one or more values.
2. Press Escape or click cancel.
3. Test both confirmation branches.

Expected:
- Dirty modal prompts confirmation.
- Choosing discard closes modal without save.
- Choosing resume keeps modal open with entered values intact.

## 6) Validate validation and feedback behavior

1. Trigger a blocking validation error (invalid/missing field).
2. Attempt save.
3. Correct values and save successfully.

Expected:
- Blocking issues prevent save and remain visible/actionable.
- On success, success feedback auto-dismisses.
- On failure, error feedback remains until dismissal or correction action.

## 7) Validate edit-mode immutability scope

1. Open Add Rule in edit context for an existing rule.
2. Attempt to edit rule name and other rule fields.

Expected:
- Rule name is non-editable.
- Other rule settings remain editable subject to validation.

## 8) Accessibility verification checks

Validate WCAG 2.1 AA expectations for:

- Keyboard-only completion path.
- Focus visibility and order.
- Label/input association.
- Error messaging announcement/visibility for corrective action.

Expected:
- Modal passes project acceptance checks for WCAG 2.1 AA dialog/form behavior.

## 9) Validate modal keyboard hook behavior (US2)

1. Open Add Rule modal.
2. Focus threshold input and press Enter.
3. Press `Ctrl+Enter` (`Cmd+Enter` on macOS).

Expected:
- Plain Enter in text inputs does not force full modal submit.
- `Ctrl/Cmd+Enter` triggers save when form is valid.

## 10) Success Criteria measurement method (SC-001, SC-002, SC-004)

- **SC-001 method**: Run 10 timed create/edit attempts for common configurations and record elapsed seconds per attempt.
- **SC-002 method**: Record first-attempt outcome over 20 attempts; pass if at least 18/20 succeed without reopening.
- **SC-004 method**: Compare `[:nixstasis, :builder, :invalid_save_attempt]` event counts pre/post change over equivalent usage windows.

## 11) Baseline capture template

- Pre-change window start/end:
- Invalid save attempts (baseline count):
- First-attempt successes (baseline count):
- Notes on workload equivalence:

## 12) Post-change capture template

- Post-change window start/end:
- Invalid save attempts (post count):
- First-attempt successes (post count):
- Timed flow samples (seconds):

## 13) SC pass/fail worksheet

- **SC-001 (<= 120s)**: PASS/FAIL
- **SC-002 (>= 90% first-attempt success)**: PASS/FAIL
- **SC-004 (>= 40% invalid-save reduction)**: PASS/FAIL
- Reduction calculation: `(baseline - post) / baseline * 100`

## Validation Run Log

- 2026-02-16: Planning artifacts generated for Add Rule modal parity feature.
- 2026-02-17: Implemented Add Rule modal create/edit parity, dirty-confirm cancel, and keyboard shortcut behavior; added LiveView coverage for create/edit/delete/validation/cancel flows.
- 2026-02-17: Remaining SC baseline/post measurement capture (SC-001/SC-002/SC-004) is pending local telemetry window execution; local Postgres service was unavailable during final validation run (`tcp connect localhost:5432 refused`).
