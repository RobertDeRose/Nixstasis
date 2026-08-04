# Add Rule Modal Improvements

## Delivery Summary

- Beads feature root: `nixstasis-inh`
- Status: implemented and documentation reconciled; validation close-out pending
- Pull request: not created; no PR action selected
- Merge commit: not merged; fast-forward delivery remains available
- Design record: [design.md](design.md)

## Delivered Capability

The `/alerts` Add/Edit Rule modal now follows the established report-modal interaction pattern for validation,
keyboard use, focus management, accessible feedback, dirty-close confirmation, and save behavior. Alert rule names are
now globally unique without regard to case; evaluation and notification semantics remain unchanged.

## User-Facing Behavior

- A single primary save action and explicit cancel path are presented.
- Validation errors remain inline, are announced to assistive technology, and preserve entered values.
- Alert rule names are enforced globally case-insensitively; duplicate names remain in the modal with actionable feedback.
- The first actionable rule-builder control receives focus when the modal opens.
- Focus stays within the active modal, including the nested discard confirmation; the confirmation receives focus on Keep Editing, exposes a high-contrast focus-visible indicator, and one Escape closes only the active layer.
- `Ctrl+Enter`/`Cmd+Enter` saves, while plain Enter in text fields does not submit the modal.
- Unchanged modals close immediately; dirty modals ask whether to keep editing or discard changes.
- Closing a modal returns focus to its opening control when the modal was opened from the rules table or Add Rule trigger.
- Successful saves expose an accessible status message before the short auto-dismiss timeout; errors remain visible until correction or action.
- Rapid or duplicate save events are ignored while a save is in flight, so one valid submission produces one save and
  one success telemetry event.

## Design Integration

The implementation refines the existing alert LiveView, `CoreComponents.modal`, `SchemaOptions`, `AlertRule`, and
`Monitoring` name-lookup patterns. The browser-only interaction uses `AshPhoenix.Form` and `Nixstasis.Domain` directly;
it does not add an Ash JSON:API route or Phoenix controller. The legacy `/alerts/rules` LiveView remains outside this
focused modal work, with route consolidation deferred.

## Operational Impact

A named migration replaces the non-unique alert-rule name index with a global case-insensitive unique index; it refuses
to migrate while existing case-insensitive conflicts remain, avoiding silent data changes. Duplicate-submit protection
is scoped to each LiveView process and protects persistence and success-feedback side effects. Validation failures remain
visible until correction or user action; success feedback continues to auto-dismiss.

## Reference and Contracts

- [Server Monitoring](../../modules/server-monitoring.md)
- [Server Web](../../modules/server-web.md)
- [Architecture Overview](../../architecture.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
- [Feature design](design.md)

## Validation Evidence

- `mise run check` passed with status 0; output: `/tmp/nixstasis-inh-alert-name-full-check-final.log`.
- `mise x -- mix precommit` passed: 611 tests, 0 failures; output: `/tmp/nixstasis-inh-13-precommit.log`.
- Focused `alerts_live_test.exs`, `core_components_test.exs`, and `reports_live_test.exs` passed: 77 tests, 0 failures.
- Alert-rule uniqueness/domain and LiveView tests passed: 27 tests, 0 failures.
- `mix ash.codegen --check` passed; named migration and alert-rule resource snapshot are aligned.
- `node --check assets/js/app.js` passed.
- Manual feature-branch browser checks confirmed `#alert-rule-name` initial focus, visible-only focus trapping, discard-dialog focus on `Keep Editing`, focus restoration after `Keep Editing`, opener-focus restoration after new/edit close, and visible success status auto-dismissal.
- Manual concurrent-tab browser checks confirmed a case-insensitive duplicate save remains in the modal with preserved values and actionable error feedback.
- `uv run scripts/check-docs.py` and `mdbook build docs` passed.
- SC-001, SC-002, and SC-004 usability measurements remain explicitly deferred: no defensible historical baseline or
  controlled observation window exists, so no metric pass/fail is claimed.

## Design Reconciliation

### Delivered as Designed

Modal parity, validation recovery, keyboard behavior, dirty-close confirmation, accessible dialog/error associations,
feedback persistence, global case-insensitive rule-name uniqueness, and one-save duplicate-submit protection were
delivered without changing alert evaluation or notification semantics.

### Intentional Changes

The feature remains a browser-only LiveView refinement. It does not consolidate `/alerts` with the legacy
`/alerts/rules` surface or introduce a new externally consumed API contract.

### Deferred Work

- Capture the planned usability baselines and timed observations when a valid operator observation window exists.
- Decide whether the legacy `/alerts/rules` route should be retired, redirected, or explicitly supported.

### Rejected or Removed Scope

Changing alert evaluation, notification delivery, or rule schema semantics, or converting UI-only interactions into Ash
JSON:API or controller routes, remains outside the feature boundary.

## Documentation Updated

- `docs/src/features/add-rule-modal-improvements/design.md`
- `docs/src/features/add-rule-modal-improvements/index.md`
- `docs/src/modules/server-monitoring.md`
- `docs/src/modules/server-web.md`
- `docs/src/planned-features.md`
- `docs/src/features/index.md`
- `docs/src/SUMMARY.md`

## Audit Trail

The reviewed design and lifecycle evidence were recorded in `1c09c4f` and `9d8cb49`. The LiveView boundary and
reader-facing documentation were clarified in `84249de`; duplicate-save protection and its regression coverage were
delivered in `d295dcf`; accessibility, nested-modal focus handling, and accessible feedback were delivered in
`2a2c274`; the first focus-management correction was delivered in `0657d3f`; and browser validation found and addressed
success-status visibility and opener-focus restoration in the current follow-up task `nixstasis-inh.14`. Global
case-insensitive rule-name uniqueness was added after validation review and is tracked by `nixstasis-inh.13`. Beads
implementation children `nixstasis-inh.7.38` and `.7.39` are closed; measurement children `.7.34` through `.7.37`
are explicitly deferred with provenance. Validation evidence is recorded on `nixstasis-inh.9`; no pull request or
merge has been created.
