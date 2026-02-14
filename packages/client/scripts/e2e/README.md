# Client E2E Harness

This directory contains the end-to-end test harness used to validate client/server integration.

- `run`: entrypoint for running the suite or selected journeys.
- `run_all_suites`: discovers suites from server (`/e2e/suites`) and runs each.
- `scaffold`: generates journey YAML + implementation stubs for new journeys.
- `journeys/`: YAML definitions for critical journeys.
- `config.example.yaml`: example configuration for local runs.

The CLI posts run metadata and results to the server. Use the returned `RunID` to fetch `/e2e/runs/:id`,
`/e2e/runs/:id/results`, or `/e2e/runs/:id/results/:journey_id/log`.

Per-journey log files use JSONL schema `e2e_log.v1` (journey start, one terminal row per step, journey completion
summary).

Run creation requires `X-E2E-Protocol-Version` (set via `--protocol-version` or config `e2e.protocol_version`).

## Runtime Suite

The `runtime` suite validates runtime client APIs and Linux-oriented Starlark telemetry flow:

- `/api/v1/devices/register`
- `/api/v1/devices/:device_id/heartbeat`
- `/api/v1/devices/:device_id/command_payloads/:ref`
- `/api/v1/devices/:device_id/command_results`
- `/api/v1/check_domain`
- JSON:API resources used by runtime reporting/alerts (`devices`, `pending_commands`, `alert_rules`, `alerts`,
  `custom_reports`, `telemetry_events`)

The runtime journey generates and executes 10+ `.stary` scripts using `exec_cmd` and validates:

- telemetry persistence to `telemetry_events`
- report rendering from stored script payloads
- alert triggering from script-derived thresholds

Performance gate:

- hard fail when script execution exceeds 5s only when:
  - `CI=true`
  - `E2E_RUNTIME_PERF_GATE=true`
  - host is Linux

## Non-Linux Hosts

If the host is not Linux, `scripts/e2e/run` automatically executes runtime E2E in an ephemeral Ubuntu Docker container
and rewrites `--api-url` to `host.docker.internal` so the containerized client reaches the host server.

## Scaffold a New Journey

Generate skeleton files in the expected client/server locations:

```bash
scripts/e2e/scaffold \
  --id runtime_disk_pressure \
  --suite runtime \
  --description "Validate disk pressure telemetry and alerting" \
  --steps runtime_register_device:runtime_device_registered,runtime_poll_with_scripts:runtime_poll_applied,runtime_verify_alert:alert_triggered,runtime_cleanup:runtime_resources_cleaned
```

Generated artifacts:

- `scripts/e2e/journeys/<id>.yaml`
- `scripts/e2e/journeys/<id>.scaffold.md`
- `internal/e2e/scaffold/<id>.go.stub`
- `../server/lib/nixstasis/e2e/scaffold/<id>.ex.stub`

Use `--force` to overwrite existing scaffold files. Use `--dry-run` to preview generated files without writing them. Use
`step_id=action:expect` in `--steps` only when you need a human-stable step label that differs from the executable
action token.

## Run All Server-Configured Suites

```bash
scripts/e2e/run_all_suites \
  --api-url http://127.0.0.1:4000 \
  --env local \
  --trigger manual \
  --protocol-version 1 \
  --reports-dir tmp/e2e/reports \
  --logs-dir tmp/e2e/logs
```

This uses server suite configuration as source of truth via `GET /e2e/suites`. If any suite fails, the command exits
non-zero.

Concrete example in repo:

- `scripts/e2e/journeys/runtime_step_labels.yaml`
- Run it: `scripts/e2e/run --suite runtime_step_labels --journey runtime_step_labels --env local --trigger manual
  --protocol-version 1`

Make helper:

```bash
DRY_RUN=1
ID=runtime_disk_pressure
SUITE=runtime
STEPS=runtime_register_device:runtime_device_registeredruntime_cleanup:runtime_resources_cleaned
make e2e-scaffold
```
