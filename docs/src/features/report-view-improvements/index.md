# Report View Improvements

## References

- Beads feature root: `nixstasis-0uj`
- Design record: [design.md](design.md)

## Delivered Capability

Custom report list and detail views provide structured metadata, explicit actions, sortable and filterable results,
saved view preferences, permission-aware fields, and resilient empty and error states.

## User-Facing Behavior

Operators can sort columns, apply typed string and numeric filters, clear state, reuse saved preferences, and confirm
report deletion. Invalid or stale preferences fall back visibly instead of breaking results.

## Design Integration

The feature refines existing reporting contexts and LiveViews. Query, permission, preference, and field-type semantics
remain server-owned and are shared with report preview contracts.

## Operational Impact

Persisted preferences improve recurring report workflows while authorization and safe fallback prevent stale state from
exposing unavailable fields or blocking access.

## Reference and Contracts

- [Server Reporting](../../modules/server-reporting.md)
- [Client-Server Interface](../../client-server-interface.md)

## Test Coverage

- `packages/server/test/nixstasis/reporting_test.exs`: reporting context behavior, permissions, and saved view
  preferences.
- `packages/server/test/nixstasis/reporting/custom_report_list_test.exs`,
  `packages/server/test/nixstasis/reporting/query_builder_test.exs`, and
  `packages/server/test/nixstasis/reporting/table_filters_test.exs`: sorting, typed filter operators, and list
  metadata.
- `packages/server/test/nixstasis_web/live/reports_live_test.exs`: stale preferences, empty states, explicit actions,
  and deletion confirmation.

## Design Reconciliation

### Delivered as Designed

Separated controls, typed filters, sorting, preference persistence, explicit actions, and safe fallback were delivered.

### Intentional Changes

Authorization and preference loading were subsequently hardened and centralized.

### Deferred Work

No feature-specific deferred scope is recorded.

### Rejected or Removed Scope

The feature did not create a new reporting data model.

## Documentation Updated

- `docs/src/modules/server-reporting.md`
- `docs/src/client-server-interface.md`
