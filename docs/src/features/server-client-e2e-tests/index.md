# Server-Client E2E Tests

## References

- Beads feature root: `nixstasis-v2g`
- Design record: [design.md](design.md)

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

## Test Coverage

- `packages/client/internal/e2e/runner_test.go` and `packages/client/internal/e2e/selector_test.go`: journey
  selection, execution, and structured logs.
- `packages/server/test/nixstasis/e2e/`: protocol validation, locking, idempotency, data policy, journey selection, log
  storage, metrics, reporting, and retention.
- `packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs` and
  `packages/server/test/nixstasis_web/controllers/e2e_run_result_controller_test.exs`: run and result API contracts,
  including unavailable logs.
- `packages/server/test/nixstasis_web/live_dashboard/e2e_log_presenter_test.exs`: LiveDashboard log presentation.
- `packages/server/test/mix/tasks/e2e_export_static_test.exs`: static export for publication.

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
