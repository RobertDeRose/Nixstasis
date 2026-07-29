# Server-Client E2E Tests

## Delivery Summary

- Beads feature root: `nixstasis-v2g`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `3549c3b2cfc79d0724ff937d44261812dbddd56c`
- Design record: `design.md`

## Delivered Capability

A client-driven E2E harness executes full suites or selected journeys against server-validated contracts and preserves
run, journey, result, metric, and log evidence for API, LiveDashboard, static, and CI review.

## User-Facing Behavior

Developers and release owners can trigger manual or CI runs, select suites and journeys, reuse idempotent requests,
inspect per-step JSONL logs, and receive typed lock, protocol, seed, cancellation, and unavailable-log outcomes.

## Design Integration

The Go client owns journey execution; Phoenix owns protocol validation, baseline seeding, environment locks, persistence,
retention, and presentation. Synthetic data remains isolated from production workflows.

## Operational Impact

One active run per environment prevents overlapping mutations. Retention bounds age, count, and bytes while static
publication preserves selected release history.

## Reference and Contracts

- [Server E2E](../../modules/server-e2e.md)
- [Client E2E Harness](../../modules/client-e2e-harness.md)
- [E2E Results](../../reference/e2e-results.md)

## Validation Evidence

Go runner tests cover selection, execution, and structured logs; server domain and controller tests cover protocol,
locking, idempotency, retention, reporting, and unavailable logs. `packages/client/internal/e2e/runner.go` corroborates
the client-owned execution boundary.

## Design Reconciliation

### Delivered as Designed

Targeted and full execution, server validation, traceable logs, locking, idempotency, reporting, and retention were
delivered.

### Intentional Changes

The final system added manifest-led GitHub Pages publication and shared static log-viewer assets.

### Deferred Work

Environment-specific journey expansion remains normal future feature work.

### Rejected or Removed Scope

Legacy client/server version request fields are rejected in favor of the explicit protocol header.

## Documentation Updated

- `README.md`
- `docs/src/modules/server-e2e.md`
- `docs/src/modules/client-e2e-harness.md`
- `docs/src/reference/e2e-results.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-v2g`. Commit `3549c3b2cfc79d0724ff937d44261812dbddd56c`
directly introduced the client-driven runner and server contract validation.
