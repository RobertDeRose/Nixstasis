# Add Rule Modal Improvements

The Add/Edit Rule dialog on `/alerts` now works like the report dialog: the same validation, keyboard shortcuts, focus
handling, accessible messages, unsaved-changes prompt, and save behavior. Alert rule names are also unique now,
ignoring case. How alerts are evaluated and sent is unchanged. The original plan is in the
[design record](design.md).

## What changed for users

- **One clear way to save or cancel.** The dialog has a single primary save button and an explicit cancel.
- **Errors you can recover from.** Validation errors appear next to the field, are announced to screen readers, and
  keep what you typed.
- **Unique names.** Two rules cannot share a name, even with different capitalization. A duplicate keeps the dialog
  open with a message saying what to fix.
- **Keyboard-friendly.**
  - Focus starts on the first rule-builder field and stays inside the dialog, including the discard prompt.
  - In the discard prompt, focus starts on **Keep Editing**, with a high-contrast focus ring, and one Escape closes only
    the topmost layer.
  - `Ctrl+Enter` or `Cmd+Enter` saves; plain Enter in a text field does not.
  - Closing the dialog returns focus to the button that opened it, whether that was **Add Rule** or a row in the rules
    table.
- **No lost work.** An unchanged dialog closes straight away; one with changes asks whether to keep editing or discard
  them.
- **Clear feedback.** A successful save shows a status message, announced to screen readers, that fades after a moment.
  Errors stay until you fix them or act on them.
- **Readable rules.** The rules table shows each condition as one `<field> <operator> <value>` expression, between the
  Rule and Actions columns.
- **One save per click.** Extra clicks while a save is running are ignored, so one valid submission makes exactly one
  save and one success event.
- **Typed fields.** Schema Field options show their type, such as `Temp (number)` or `Status (string)`, and
  `(unknown)` when the type is not known.
- **Sensible operators.** Switching the Schema Field replaces an operator that no longer fits with the first one that
  does. If the field did not change, an invalid operator still shows an error you can act on.

## How it fits in

The dialog builds on the existing alert LiveView, the shared `CoreComponents.modal`, `SchemaOptions`, `AlertRule`, and
`Monitoring`'s name lookup. It works entirely in the browser through `AshPhoenix.Form` and `Nixstasis.Domain`, with no
new JSON:API route or controller. The `/alerts/rules` page and its editor routes came later, with
[Bounded LiveView Catalog Reads](../bounded-liveview-catalog-reads/index.md).

## Running it

A named migration replaces the old alert-rule name index with a unique, case-insensitive one. If existing rule names
already clash when case is ignored, the migration stops rather than changing any data, so rename them first.

The protection against double saves works per browser session.

## Differences from the design

The feature stayed a browser-only change and did not merge `/alerts` with the rules page. That merge was done later by
[Bounded LiveView Catalog Reads](../bounded-liveview-catalog-reads/index.md), without adding an external API.

## Not included

- The usability measurements in the design (SC-001, SC-002, and SC-004) were not taken: there was no reliable baseline
  or controlled observation window, so no result is claimed.
- Alert evaluation, notification delivery, and the rule schema did not change.
- None of the dialog's actions are available as JSON:API or controller routes.

## Tests

- `packages/server/test/nixstasis_web/live/alerts_live_test.exs`: validation, keyboard save, the unsaved-changes prompt,
  double-save protection, type labels, operator recovery, and the rules table.
- `packages/server/test/nixstasis_web/components/core_components_test.exs`: the shared dialog component and its
  accessibility.
- `packages/server/test/nixstasis_web/live/reports_live_test.exs`: the report dialog this one copies.
- `packages/server/test/nixstasis/monitoring/alert_rule_uniqueness_test.exs`: case-insensitive unique names.
- `packages/server/test/nixstasis/monitoring/alert_rule_test.exs`: alert-rule behavior.
- `mix ash.codegen --check`: the migration and resource snapshot match.
- `node --check assets/js/app.js`: the dialog's JavaScript parses.
- Manual browser checks: initial focus on `#alert-rule-name`, focus trapping, focus on **Keep Editing**, one Escape per
  layer, focus returning to the opener, and the success message fading.
- Manual two-tab check: saving a duplicate name in a second tab keeps the dialog open, with the values kept and a clear
  error.

## Related pages

- [Server Monitoring](../../modules/server-monitoring.md)
- [Server Web](../../modules/server-web.md)
- [Architecture Overview](../../architecture.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
