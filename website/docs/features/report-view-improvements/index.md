# Report View Improvements

The report list and report pages are easier to work with: clear details about each report, explicit actions, results
you can sort and filter, saved view settings, fields that respect permissions, and helpful empty and error states. The
original plan is in the [design record](design.md).

## What changed for users

- Sort by any column, filter with text and number operators, and clear everything in one go.
- Your sorting and filters are saved and come back next time.
- Deleting a report asks for confirmation.
- If saved settings no longer fit, for example a field was removed, the page says so and falls back to defaults instead
  of breaking.

## How it fits in

The feature builds on the existing reporting context and LiveViews. Queries, permissions, saved settings, and field
types are all handled on the server, the same way as for the report results API.

## Running it

Saved settings make repeated report work quicker. Permission checks and the safe fallback mean old settings can never
reveal fields you cannot see, or lock you out of a report.

## Differences from the design

Permission checks and loading of saved settings were later tightened and gathered in one place.

## Not included

Reports use the existing data model; there is no new reporting store.

## Tests

- `packages/server/test/nixstasis/reporting_test.exs`: the reporting context, permissions, and saved settings.
- `packages/server/test/nixstasis/reporting/custom_report_list_test.exs`, `query_builder_test.exs`, and
  `table_filters_test.exs`: sorting, typed filters, and list details.
- `packages/server/test/nixstasis_web/live/reports_live_test.exs`: outdated settings, empty states, actions, and
  delete confirmation.

## Related pages

- [Server Reporting](../../modules/server-reporting.md)
- [Client-Server Interface](../../client-server-interface.md)
