# Nixstasis Client (Go)

The Nixstasis client is a lightweight IoT monitoring agent written in Go. It replaces the original Bash prototype and
now provides embedded Starlark scripting for telemetry, durable identity, and FRP tunnel control.

## Features

- **Auto-Registration**: Registers with the Nixstasis server on first boot and persists a device UUID.
- **Starlark Scripts**: Discovers and runs `stary` scripts to collect telemetry.
- **Remote Access**: Manages `frpc` tunnels on-demand based on server directives.
- **Resilient**: Handles network interruptions and retries automatically.

## Project Layout

- `cmd/nixstasis`: CLI entry point for the `nixstasis` binary (`register`, `poll`, etc.).
- `internal`: Core packages (config, identity, transport, telemetry, script, frp).
- `bin`: Packaging scripts and helper utilities.

## Building

### Prerequisites

- Go 1.25+
- Make

### Commands

```bash
mise run build      # Build binary locally (bin/nixstasis)
mise run build:local # Run the client CLI locally
mise run test       # Run unit tests with race detector and coverage
mise run test:coverage # Print coverage summary from coverage.out
```

## Usage

```bash
bin/nixstasis register
bin/nixstasis poll
```

## E2E Testing

The client includes a lightweight E2E harness for validating client/server integration.
An entire suite of journeys can be run like the following:

```bash
scripts/e2e/run --suite full --env local --trigger manual --protocol-version 1
scripts/e2e/run --suite full --env local --trigger manual --protocol-version 1 --idempotency-key local-full-001
scripts/e2e/run --suite runtime --env local --trigger manual --protocol-version 1
scripts/e2e/run --suite runtime_step_labels --journey step_labels --env local --trigger manual --protocol-version 1
```

An individual journey can be like the following:

```bash
scripts/e2e/run --journeys auth,dashboard --env local --protocol-version 1
scripts/e2e/run --journey auth --env local --protocol-version 1
```

To aid in creating new suites of end-to-end tests, there is a scaffolding script:

```bash
scripts/e2e/scaffold --id disk_pressure --suite runtime --description "Validate disk pressure telemetry and alerting" \
--steps \
"register_device:device_registered,"\
"poll_with_scripts:poll_applied,"\
"verify_alert:alert_triggered,"\
"cleanup:resources_cleaned"
```

To see what the scaffold will do without doing it, there is a `--dry-run` flag

```bash
scripts/e2e/scaffold  --dry-run --id runtime_disk_pressure --steps register_device:device_registered
```

```bash
# optional custom step labels (only when needed):
scripts/e2e/scaffold --id runtime_disk_pressure --steps register_phase=register_device:device_registered
```

Configuration lives in `scripts/e2e/config.example.yaml` and can be customized per environment. The CLI posts runs and
results to the server; use the printed `RunID` to query `/e2e/runs/:id`, `/e2e/runs/:id/results`, and
`/e2e/runs/:id/results/:journey_id/log`.

Journey logs are JSONL records in schema `e2e_log.v1`:

- journey start envelope with run metadata
- one terminal step record per action (`passed|failed`) with `duration_ms`
- journey completion summary with step totals and failure metadata

The runtime suite generates and executes 10+ Linux-oriented Starlark scripts (real `exec_cmd` usage) and validates:

- runtime API contracts (`register`, `heartbeat`, `command_payloads`, `command_results`, `check_domain`)
- telemetry persistence and report queryability
- alert triggering from script data

Runtime suite journeys:

- `runtime_linux_telemetry` (full telemetry/report/alert flow)
- `runtime_transport_contract` (transport endpoint parity + command payload/result lifecycle)
- `runtime_transport_negative` (transport negative-path assertions for 404/400 behavior)

On non-Linux hosts, `scripts/e2e/run` automatically runs runtime E2E in an ephemeral Ubuntu Docker container using
`host.docker.internal` to reach the host server.

## Configuration

Configuration is loaded from `/etc/nixstasis/config.yaml`.

```yaml
api:
  url: "http://localhost:4000" # Nixstasis server URL

poll:
  interval: 10s

scripts:
  dir: "/usr/libexec/nixstasis/scripts"
```

## Packaging

This project is migrating to GoReleaser for archive, `.deb`, and `.rpm` outputs.

1. `scripts/fetch_frpc.sh` stages the bundled `frpc` binary.
2. `.goreleaser.yaml` packages the binary, config, and service assets under `nixstasis` paths.

## Rewrite Status

From `specs/004-rewrite-client-go/tasks.md`, the Go rewrite is largely complete. Remaining items:

- T027: FRP lifecycle hooks for connection metadata
