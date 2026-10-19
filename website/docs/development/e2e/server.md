# Server E2E

The `Nixstasis.E2E` context is the server half of the end-to-end tests. It tracks each run from start to finish, makes
sure only one run uses an environment at a time, seeds test data, stores journey results and logs, cleans up old runs,
and exports static reports.

## Owns

- `Nixstasis.E2E` in `packages/server/lib/nixstasis/e2e.ex` and its modules under
  `packages/server/lib/nixstasis/e2e/`: `Protocol`, `EnvironmentLocks`, `JourneySelection`, `ExpectationRegistry`,
  `DataPolicy`, `LogStore`, `Run`, `RunResult`, `RetentionWorker`, and `Metrics`.
- The `mix e2e.export_static` task, which renders runs into static report pages.
- The shared log viewer in `packages/shared/e2e_log_viewer/` (`viewer.js` and `viewer.css`). The static export embeds
  it in report pages, and the LiveDashboard E2E page loads the same viewer.

## Entry points

- The `/e2e` routes in `NixstasisWeb.E2ERunController` and `NixstasisWeb.E2ERunResultController`: list suites, list
  and create runs, show and cancel a run, submit and read results, and fetch a journey log. The routes and their
  formats are in [E2E API](api.md).
- Context functions: `create_run/1`, `list_runs_for_runner/2`, `get_run_for_runner/2`, `submit_results/2`,
  `fetch_result_log/2`, and `prune_retention/1`.
- The LiveDashboard E2E page at `/dev/dashboard` in development.

## Boundaries

- **Enablement:** `/e2e` is disabled unless `NIXSTASIS_E2E_ENABLED=true`, which also requires
  `NIXSTASIS_E2E_RUNNER_ID` and a `NIXSTASIS_E2E_RUNNER_TOKEN` of at least 32 bytes.
- **Runner ownership:** every request carries `X-E2E-Runner-ID` and `Authorization: Bearer`, independent of operator
  roles. Runs are stamped with the authenticated runner, and only that runner can read, cancel, or submit to them.
  Runs created before runner ownership was added belong to `:unowned`, which no runner can match. Any of those that
  were still queued or running were cancelled, and their locks released.
- **Run creation:** `POST /e2e/runs` requires `X-E2E-Protocol-Version`, validates the protocol, environment, suite,
  journeys, and action expectations, runs the configured seed script, and holds an environment lock for the run. Typed
  errors include `environment_locked`, `protocol_mismatch`, `invalid_action_expectation`, `seed_failed`,
  `invalid_request`, and `database_error`.
- **Listing:** `GET /e2e/runs` returns at most the 100 most recent runs owned by the caller.
- **Not part of the JSON:API:** `/e2e` is a plain controller API, because its on/off switch, protocol checks, locking,
  seeding, and log retention don't fit Ash's action model.
- **Assets:** seed scripts and journey definitions load from the release `priv` directory; the server image packages
  the client journey YAML under `priv/e2e/journeys`.
- The client side is described in [Client E2E Harness](client-harness.md), and published reports in
  [E2E Results](results.md).
