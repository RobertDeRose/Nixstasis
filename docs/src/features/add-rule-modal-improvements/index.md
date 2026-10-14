# Add Rule Modal Improvements

## References

- Beads feature root: `nixstasis-inh`
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
- The rules table presents each condition as one readable `<field> <operator> <value>` expression between the Rule and Actions columns.
- Rapid or duplicate save events are ignored while a save is in flight, so one valid submission produces one save and
  one success telemetry event.
- Schema Field options show the active schema type beside each label, such as `Temp (number)` and `Status (string)`;
  unknown types are explicit as `(unknown)`.
- Changing the Schema Field replaces an incompatible stale operator with the first valid operator before validation and
  save, while unchanged-field invalid input remains actionable.

## Design Integration

The implementation refines the existing alert LiveView, `CoreComponents.modal`, `SchemaOptions`, `AlertRule`, and
`Monitoring` name-lookup patterns. The browser-only interaction uses `AshPhoenix.Form` and `Nixstasis.Domain` directly;
it does not add an Ash JSON:API route or Phoenix controller. The modal work did not itself alter the route boundary;
the later bounded LiveView catalog reads feature now owns the canonical `/alerts/rules` LiveView index and nested editor
routes.

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

## Test Coverage

- `packages/server/test/nixstasis_web/live/alerts_live_test.exs`: modal validation, keyboard save, dirty-close
  confirmation, duplicate-submit protection, schema type labels, operator recovery, and rules table presentation.
- `packages/server/test/nixstasis_web/components/core_components_test.exs`: shared modal component and accessibility
  behavior.
- `packages/server/test/nixstasis_web/live/reports_live_test.exs`: report-modal pattern the alert modal mirrors.
- `packages/server/test/nixstasis/monitoring/alert_rule_uniqueness_test.exs`: global case-insensitive rule-name
  uniqueness.
- `packages/server/test/nixstasis/monitoring/alert_rule_test.exs`: alert-rule domain behavior.
- `mix ash.codegen --check`: named migration and alert-rule resource snapshot stay aligned.
- `node --check assets/js/app.js`: modal hook JavaScript parses.
- Manual browser check: initial focus on `#alert-rule-name`, focus trapping, discard-dialog focus on `Keep Editing`,
  one Escape closing only the active layer, opener-focus restoration, and visible success status auto-dismissal.
- Manual concurrent-tab check: a case-insensitive duplicate save remains in the modal with preserved values and
  actionable error feedback.

## Design Reconciliation

### Delivered as Designed

Modal parity, validation recovery, keyboard behavior, dirty-close confirmation, accessible dialog/error associations,
feedback persistence, global case-insensitive rule-name uniqueness, one-save duplicate-submit protection, first-valid-
operator recovery, and schema type labels were delivered without changing alert evaluation or notification semantics.

### Intentional Changes

The feature remains a browser-only LiveView refinement and did not itself consolidate `/alerts` with the rules surface.
The later bounded LiveView catalog reads feature delivered the canonical `/alerts/rules` surface without introducing a
new externally consumed API contract.

### Deferred Work

- SC-001, SC-002, and SC-004 usability measurements were deferred: no defensible historical baseline or controlled
  observation window exists, so no metric result is claimed. Capture the planned usability baselines and timed
  observations when a valid operator observation window exists.
- Route consolidation is delivered by the bounded LiveView catalog reads feature; this feature retains no route-decision
follow-up.

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
