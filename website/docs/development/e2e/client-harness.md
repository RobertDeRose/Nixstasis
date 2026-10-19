# Client E2E Harness

The client half of the end-to-end tests. It asks the server to start a run, plays each journey against a real client,
writes logs, and sends the results back.

## Owns

- `packages/client/internal/e2e/`: configuration, journey loading and selection, the runner, the journey executors, and
  the `/e2e` API client (`api.go`).
- `packages/client/scripts/e2e/`: the `run` entrypoint, `run_all_suites`, the `scaffold` journey generator, journey YAML
  under `journeys/`, and `config.example.yaml`.

## Entry points

- `scripts/e2e/run` runs a suite or selected journeys; `run_all_suites` discovers suites from `GET /e2e/suites` and runs
  each one.
- `scripts/e2e/scaffold` generates the YAML and stubs for a new journey.

## Boundaries

- **Authentication:** every `/e2e` request carries `X-E2E-Runner-ID` and `Authorization: Bearer`. The runner ID comes
  from `NIXSTASIS_E2E_RUNNER_ID` or `e2e.runner_id`; the token is read only from `NIXSTASIS_E2E_RUNNER_TOKEN`, never
  from YAML or arguments.
- **Transport:** requests use the same connection policy as [Client Transport](../../modules/client-transport.md).
- **Protocol:** run creation sends `X-E2E-Protocol-Version`; the server rejects mismatches
  ([Server E2E](server.md)).
- **Logs:** each journey writes JSONL in the `e2e_log.v1` schema: a journey start row, one row per step, and a
  completion summary.
- **Platforms:** runtime journeys run natively on Linux; elsewhere the harness falls back to Apple Container, Docker,
  then Podman.
