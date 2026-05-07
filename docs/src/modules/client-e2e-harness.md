# Client E2E Harness

## Language

- Go and shell scripts.

## Runtime Context

- Client-side E2E runner for validating client/server integration.

## Purpose

- Loads E2E configuration and journey specs, creates server-side E2E runs, executes journeys, writes JSONL logs, and submits results.

## Key Files

- `packages/client/scripts/e2e/run`
- `packages/client/scripts/e2e/run_all_suites`
- `packages/client/scripts/e2e/scaffold`
- `packages/client/scripts/e2e/main.go`
- `packages/client/scripts/e2e/config.example.yaml`
- `packages/client/scripts/e2e/journeys/*.yaml`
- `packages/client/internal/e2e/api.go`
- `packages/client/internal/e2e/runner.go`
- `packages/client/internal/e2e/journey.go`
- `packages/client/internal/e2e/journey_executor.go`
- `packages/client/internal/e2e/selector.go`
- `packages/client/internal/e2e/runtime_scripts.go`
- `packages/server/lib/nixstasis/e2e.ex`

## Public Interfaces

- CLI scripts:
  - `scripts/e2e/run`
  - `scripts/e2e/run_all_suites`
  - `scripts/e2e/scaffold`
- Go E2E package interfaces:
  - `api.go` API client for `/e2e` endpoints.
  - `runner.go` run orchestration.
  - `journey_executor.go` action execution and JSONL log emission.
  - `selector.go` suite/journey selection.

## Dependencies

### Internal

- `internal/e2e`
- `internal/transport`
- `internal/script`
- Server E2E API and configuration.

### External

- YAML parsing through `go.yaml.in/yaml/v3`.
- Runtime container fallback mentioned in `packages/client/README.md`: Apple Container, Docker, then Podman for non-Linux runtime E2E.

## Client-Server Interaction Details

- Creates runs through `POST /e2e/runs`.
- Uses `X-E2E-Protocol-Version`.
- Fetches suite catalog through `GET /e2e/suites`.
- Submits journey outcomes through `POST /e2e/runs/:id/results`.
- Logs can be inspected through `GET /e2e/runs/:id/results/:journey_id/log`.

Traceable references:

- `README.md:53-225`
- `packages/client/README.md:42-114`
- `packages/client/internal/e2e/api.go`
- `packages/client/internal/e2e/runner.go`
- `packages/client/internal/e2e/journey_executor.go`
