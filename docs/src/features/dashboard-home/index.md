# Dashboard Home

## Delivery Summary

- Beads feature root: `nixstasis-019`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `79c6439fe1ff0f2f98aa05e9012742a04f578ec7`
- Design record: `design.md`

## Delivered Capability

The default LiveView dashboard presents fleet totals, connectivity, pending approvals, active alerts, and direct
navigation into operational workflows.

## User-Facing Behavior

Operators receive meaningful zero and degraded states, clickable summary cards, and refreshed counts as registrations,
heartbeats, approvals, alerts, and device deletion events occur.

## Design Integration

The dashboard uses server contexts and LiveView PubSub updates rather than duplicating device-state logic. Connectivity
counts share the established heartbeat freshness model.

## Operational Impact

Debounced updates reduce refresh pressure during heartbeat bursts while retaining timely situational awareness.

## Reference and Contracts

- [Introduction](../../README.md)
- [Server Web](../../modules/server-web.md)
- [Server Monitoring](../../modules/server-monitoring.md)

## Validation Evidence

Dashboard LiveView tests cover seeded counts, navigation, empty data, PubSub updates, unknown messages, and filter/count
separation. `packages/server/lib/nixstasis_web/live/dashboard_live/index.ex` corroborates the delivered behavior.

## Design Reconciliation

### Delivered as Designed

Fleet summaries, workflow navigation, real-time updates, and resilient states were delivered.

### Intentional Changes

Later work added debouncing, explicit deletion broadcasts, and selectable UI palettes without changing dashboard intent.

### Deferred Work

No feature-specific deferred scope remains.

### Rejected or Removed Scope

The dashboard does not introduce a separate analytics store or connectivity model.

## Documentation Updated

- `docs/src/README.md`
- `docs/src/modules/server-web.md`
- `docs/src/modules/server-monitoring.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-019`. Commit `79c6439fe1ff0f2f98aa05e9012742a04f578ec7`
directly reconciled device filtering and real-time dashboard counts.
