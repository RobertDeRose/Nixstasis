# Server-Client E2E Tests

An end-to-end test harness, driven by the client, runs whole suites or chosen journeys against the server, which checks
every request. Each run keeps its journeys, results, metrics, and logs, so they can be reviewed through the API,
LiveDashboard, static reports, or CI. The original plan is in the [design record](design.md).

## What changed for users

Developers and release owners can start runs by hand or from CI, choose suites and journeys, repeat a request safely
without starting a second run, and read a JSONL log of every step. Locks, protocol mismatches, seed failures,
cancellations, and missing logs each come back as a clear, typed error.

## How it fits in

The client runs the journeys. Phoenix checks the protocol, seeds baseline data, locks environments, stores results,
cleans up old runs, and presents the results. Test data is kept apart from real production workflows.

## Running it

Only one run can be active in an environment at a time, so runs never trample each other's data. Old runs are cleaned
up by age, count, and total size, while published static reports keep a record of selected releases.

## Differences from the design

Reports are published to GitHub Pages from a manifest, and the static reports and LiveDashboard share one log viewer.

## Not included

Runs carry no client or server version fields; the protocol is set only with the `X-E2E-Protocol-Version` header.

## Tests

- `packages/client/internal/e2e/runner_test.go` and `selector_test.go`: choosing and running journeys, and structured
  logs.
- `packages/server/test/nixstasis/e2e/`: protocol checks, locking, repeated requests, data policy, journey selection,
  log storage, metrics, reporting, and cleanup.
- `packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs` and `e2e_run_result_controller_test.exs`:
  the run and result API, including missing logs.
- `packages/server/test/nixstasis_web/live_dashboard/e2e_log_presenter_test.exs`: how LiveDashboard shows logs.
- `packages/server/test/mix/tasks/e2e_export_static_test.exs`: exporting static reports for publishing.

## Related pages

- [Server E2E](../../development/e2e/server.md)
- [Client E2E Harness](../../development/e2e/client-harness.md)
- [E2E Results](../../development/e2e/results.md)
- [Data Flow](../../data-flow.md#e2e-run-lifecycle)
