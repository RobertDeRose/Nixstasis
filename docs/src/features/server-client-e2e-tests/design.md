# Server-Client E2E Tests

## Feature Name

`server-client-e2e-tests`

## Goal

Provide a repeatable client-driven end-to-end harness that validates Nixstasis
client/server compatibility before release.

## Users

- Release owners validating release readiness.
- Developers running targeted journeys during feature work.
- Stakeholders reviewing auditable integration results.

## Requirements

- Run a full suite or selected journey subset from manual or CI triggers.
- Use synthetic test data only.
- Require `X-E2E-Protocol-Version` and reject legacy client/server version fields.
- Record runs, journeys, results, metadata, logs, and failure points.
- Enforce environment locks so only one active run uses a given environment at a time.
- Provide per-journey logs and summary reports through API/UI/static export paths.
- Support idempotent run creation for repeated invocations.
- Provide retention and unavailable-log behavior.

## Proposed Design

The client owns journey specs and executes steps. The server validates run
contracts, seeds baseline data, stores runs/results/log references, exposes run
APIs, and renders LiveDashboard/static reports. Operational usage is documented
in the top-level README and module docs.

## Validation

- Full suite completes under the documented target in standard environments.
- Targeted journeys run without executing unrelated journeys.
- Unsupported protocol versions are rejected.
- Environment locking prevents overlapping runs.
- Logs remain traceable or return typed unavailable states after pruning.
