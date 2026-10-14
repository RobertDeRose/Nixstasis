# Dashboard Home

## References

- Beads feature root: `nixstasis-019`
- Design record: [design.md](design.md)

## Delivered Capability

The default LiveView dashboard presents fleet totals, connectivity, pending approvals, active alerts, and direct
navigation into operational workflows.

## User-Facing Behavior

Operators receive meaningful zero and degraded states, clickable summary cards, and refreshed counts as registrations,
heartbeats, approvals, alerts, and device deletion events occur.

## Design Integration

The dashboard uses server contexts and LiveView PubSub updates rather than duplicating device-state logic. Connectivity
counts share the established heartbeat freshness model. Device-backed aggregates are evaluated with the verified Ash
device-data actor, so scoped operators see only totals for authorized device IDs and invalid scope fails closed.

## Operational Impact

Debounced updates reduce refresh pressure during heartbeat bursts while retaining timely situational awareness.

## Reference and Contracts

- [Introduction](../../README.md)
- [Server Web](../../modules/server-web.md)
- [Server Monitoring](../../modules/server-monitoring.md)

## Test Coverage

- `packages/server/test/nixstasis_web/live/dashboard_live_test.exs`: seeded counts, navigation, empty data, PubSub
  updates, unknown messages, and filter/count separation.
- `packages/server/test/nixstasis/devices/stats_test.exs`: dashboard device count aggregates.

## Design Reconciliation

### Delivered as Designed

Fleet summaries, workflow navigation, real-time updates, and resilient states were delivered.

### Intentional Changes

Later work added debouncing, explicit deletion broadcasts, selectable UI palettes, and device-scoped aggregate
authorization without changing dashboard intent.

### Deferred Work

No feature-specific deferred scope remains.

### Rejected or Removed Scope

The dashboard does not introduce a separate analytics store or connectivity model.

## Documentation Updated

- `docs/src/README.md`
- `docs/src/modules/server-web.md`
- `docs/src/modules/server-monitoring.md`
