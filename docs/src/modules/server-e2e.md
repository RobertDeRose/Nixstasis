# Server E2E

## Language

- Elixir.

## Runtime Context

- Server E2E control API, data lifecycle, log retention, LiveDashboard reporting.

## Purpose

- Manages E2E test run lifecycle, suite listing, protocol validation, idempotency, environment locks, seed execution, journey result ingestion, log storage, log retrieval, and retention pruning.

## Key Files

- `packages/server/lib/nixstasis/e2e.ex`
- `packages/server/lib/nixstasis/e2e/run.ex`
- `packages/server/lib/nixstasis/e2e/run_result.ex`
- `packages/server/lib/nixstasis/e2e/protocol.ex`
- `packages/server/lib/nixstasis/e2e/journey_selection.ex`
- `packages/server/lib/nixstasis/e2e/expectation_registry.ex`
- `packages/server/lib/nixstasis/e2e/environment_locks.ex`
- `packages/server/lib/nixstasis/e2e/log_store.ex`
- `packages/server/lib/nixstasis/e2e/retention_worker.ex`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_result_controller.ex`
- `packages/server/lib/nixstasis_web/plugs/e2e_enabled.ex`
- `packages/server/lib/nixstasis_web/live_dashboard/e2e_page.ex`
- `packages/server/lib/mix/tasks/e2e.export_static.ex`

## Public Interfaces

- `Nixstasis.E2E.list_runs/0`
- `Nixstasis.E2E.list_suites/0`
- `Nixstasis.E2E.get_run!/1`
- `Nixstasis.E2E.get_run/1`
- `Nixstasis.E2E.prune_retention/1`
- `Nixstasis.E2E.list_results/1`
- `Nixstasis.E2E.create_run/1`
- `Nixstasis.E2E.cancel_run/1`
- `Nixstasis.E2E.delete_runs/1`
- `Nixstasis.E2E.record_result/3`
- `Nixstasis.E2E.submit_results/2`
- `Nixstasis.E2E.store_log/3`
- `Nixstasis.E2E.fetch_result_log/2`
- `Nixstasis.E2E.RetentionWorker.start_link/1`

## Dependencies

### Internal

- `Nixstasis.E2E.DataPolicy`
- `Nixstasis.E2E.EnvironmentLocks`
- `Nixstasis.E2E.ExpectationRegistry`
- `Nixstasis.E2E.JourneySelection`
- `Nixstasis.E2E.LogStore`
- `Nixstasis.E2E.Protocol`
- `Nixstasis.E2E.Run`
- `Nixstasis.E2E.RunResult`
- `Nixstasis.Repo`

### External

- Ecto.Query
- GenServer
- Phoenix Controller rendering
- LiveDashboard extension page

## Client-Server Interaction Details

- `/e2e` routes are retained-controller workflow endpoints. They stay outside Ash
  JSON:API unless a future action model can preserve the E2E gate,
  protocol-version checks, environment locking, seed execution, typed errors,
  result ingestion, and log-retention semantics without weakening the harness
  contract.
- `POST /e2e/runs` reads `X-E2E-Protocol-Version`, validates protocol/environment/suite/journeys/action-expect pairs, runs configured seed script, creates run rows, and returns `201` on success.
- Run creation can return typed errors including `environment_locked`, `protocol_mismatch`, `invalid_action_expectation`, `seed_failed`, `invalid_request`, and `database_error`.
- `POST /e2e/runs/:id/results` stores journey outcomes and updates run status.
- `GET /e2e/runs/:id/results/:journey_id/log` retrieves log content or typed log-unavailable errors.
- Production deployments disable E2E endpoints by default through `NixstasisWeb.Plugs.E2EEnabled` unless `NIXSTASIS_E2E_ENABLED=true`.

Traceable references:

- `packages/server/lib/nixstasis/e2e.ex:1-420`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex:1-93`
- `packages/server/lib/nixstasis_web/router.ex:68-79`
- `deploy/compose/README.md:12-14`
