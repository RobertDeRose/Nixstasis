# Quickstart: Server-Client End-to-End Tests

**Date**: 2026-02-10

## Prerequisites

- Postgres running for the server.
- Elixir and Go toolchains installed (per package READMEs).
- Synthetic baseline test data available in the test environment.

## Local Manual Run (Developer)

1. Start the server:
   - `cd packages/server`
   - `mix setup`
   - `mix phx.server`
2. Build or run the client:
   - `cd packages/client`
   - `make build`
3. Configure the client to point at the local server (`api.url: http://localhost:4000`).
4. Run the E2E harness (full suite or a single journey):
   - Full suite: `scripts/e2e/run --suite full --env local --trigger manual`
   - Single journey: `scripts/e2e/run --journey auth --env local`
   - Multiple journeys: `scripts/e2e/run --journeys auth,dashboard --env local`
   - Custom config: `scripts/e2e/run --config scripts/e2e/config.example.yaml`

## CI/Automation Run

- CI triggers should call the same E2E harness with `--trigger ci` and an environment label.
- Ensure the environment is reset and seeded before each run.

## Outputs

- Summary report per run with pass/fail by journey.
- Per-journey logs for debugging.
- Run metadata (environment, versions, timestamps).
