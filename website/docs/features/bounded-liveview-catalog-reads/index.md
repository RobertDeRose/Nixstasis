# Bounded LiveView Catalog Reads

Large lists in the web UI now stay fast however big the fleet gets, because the database does the searching, sorting,
and paging, and pages only ever load what they show. The original plan is in the [design record](design.md).

- **Device picker:** searches only devices you can access, always in the same order, and shows at most 50 at a time.
  Devices you have already selected stay selected across searches. Script tests, deployments, and retries all share
  the 250-device limit, and an old run's device count is checked before its devices are loaded.
- **Alert rules:** managed at `/alerts/rules`, with filtering, sorting, counts, and 50-row pages done in the database.
  `/alerts` shows active alerts.
- **Reports:** the list is filtered, sorted, and paged 50 at a time in the database, keeps its state in the URL, and
  shows short summaries with at most 25 field labels.
- **Command policy previews:** load only the selected entries, read only the columns they need, and refuse a selection
  that resolves to more than 2,500 commands or 10,000 source rows before building the policy.

## What changed for users

- Device search waits for you to stop typing, and keeps your selections and their labels as the results change.
- A device selection that is forged, malformed, outside your access, or out of date is refused, and nothing is queued.
- Rule and report filters, sorting, and page numbers live in the URL, so you can bookmark or share them. An invalid
  page number takes you to a valid page.
- A command policy selection that is too large is refused as a whole, with a message telling you to narrow it, instead
  of quietly dropping commands.
- Permissions, schema validation, retries, queueing, editing and deleting reports, and dialog accessibility all work
  as before.

## How it fits in

Following the design, permission checks, search, filtering, sorting, counting, limits, and column selection all happen
before any rows reach the page. The existing join, foreign-key, array and JSONB GIN, and telemetry indexes already cover
the policy and catalog lookups. A named migration adds only the ordering indexes the new device picker, alert rule, and
report queries actually use.

## Running it

There are no new settings. Apply the new migration as part of a normal server upgrade.

The focused tests measure query counts and payload sizes, through `[:nixstasis, :repo, :query]` telemetry and term
sizes. If you hit a result or resolution limit, narrow your search or policy selection.

## Differences from the design

- `/alerts/rules` is the only place to manage rules; the duplicate page was removed.
- The [query evidence](query-evidence.md) is kept as a lasting record, because accepting the feature required measured
  query counts, row counts, payload sizes, and query plans.
- Alert rules are ordered by `(product_name, id)`, which matches the default sort.

## Not included

- No list is ever silently cut short: policy resolutions, device selections, report rows, and alert rules are all
  either complete or refused.
- No speculative indexes were added for policies or the catalog.
- There is no shared pagination framework, and no group or bulk targeting for scripts.

## Tests

- `packages/server/test/nixstasis/bounded_catalog_query_evidence_test.exs`: the ordering indexes exist, device and
  report reads take one query, policy previews are bounded, and oversized selections are refused before a policy is
  built.
- `packages/server/test/nixstasis_web/bounded_catalog_live_evidence_test.exs`: row and payload limits on the real
  `/alerts/rules` page.
- `packages/server/test/nixstasis_web/live/script_live_test.exs`: device picker search, the 50-row limit, kept
  selections, and refused selections.
- `packages/server/test/nixstasis_web/live/alerts_live_test.exs`: the `/alerts/rules` route, filtering, and paging.
- `packages/server/test/nixstasis/reporting/custom_report_list_test.exs` and
  `packages/server/test/nixstasis_web/live/reports_live_test.exs`: report paging, sorting, and summaries.
- `packages/server/test/nixstasis/command_allowlists/policy_resolver_test.exs` and
  `packages/server/test/nixstasis_web/live/command_policy_live_test.exs`: policy preview scope and limits.
- `mix compile --no-optional-deps --warnings-as-errors` and `mix ash.codegen --check`.

## Related pages

- [Bounded catalog query evidence](query-evidence.md)
- [Server Devices](../../modules/server-devices.md)
- [Server Web](../../modules/server-web.md)
- [Server Scripts](../../modules/server-scripts.md)
- [Server Monitoring](../../modules/server-monitoring.md)
- [Server Reporting](../../modules/server-reporting.md)
- [Stary Script Workbench](../../operations/script-workbench.md)
- [Command Policies](../../operations/command-policies.md)
