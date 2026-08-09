# Bounded LiveView Catalog Reads

## Delivery Summary

- Beads feature root: `nixstasis-mol-iuv`
- Implementation coordinator: `nixstasis-mol-594`
- Status: delivered
- Pull request: not created
- Merge commit: `69e0e2c772c5f61a6afce8914adc6cb03e31b739` (fast-forward delivery)
- Design record: [design.md](design.md)

## Delivered Capability

Nixstasis now keeps large LiveView catalogs bounded at the SQL and rendering boundaries. Device
picker results are authorization-scoped, searchable, deterministic, and limited to 50 rows while
selected targets remain available across searches. Script queue, deployment, and retry paths share
the 250-device limit and preflight historical targets before loading them.

Alert rule management is canonical at `/alerts/rules`; rules use SQL filtering, sorting, counts, and
50-row pagination. `/alerts` remains the active-alert surface. Report indexes use SQL filtering,
deterministic sorting, 50-row pagination, URL-preserved state, and compact summaries limited to 25
field labels. Manual and catalog command-policy previews scope selected IDs in SQL, use narrow
projections, and reject more than 2,500 resolved commands or 10,000 source rows before materializing
a policy.

## User-Facing Behavior

- Device search is debounced and preserves selected IDs and labels across result changes.
- Forged, malformed, unauthorized, or stale device selections fail closed without queueing work.
- Rule and report filters, sort state, and page state are addressable in the URL; invalid pages
  recover to a valid page.
- Oversized command-policy selections fail atomically with actionable narrowing guidance rather than
  silently truncating commands.
- Existing authorization, schema validation, retry, queue, report edit/delete, and modal
  accessibility behavior remains intact.

## Design Integration

The implementation follows the feature design's deep boundary: authorization, search/filter,
sort, count, limit, and projection happen before Ash/Ecto rows enter LiveView state. Existing
join, foreign-key, array-GIN, JSONB-GIN, and telemetry indexes remain responsible for policy and
catalog compatibility lookups. A named migration adds only the final device-picker, alert-rule,
and report ordering indexes supported by the delivered SQL shapes.

## Operational Impact

No new configuration is required. The new migration must be applied during normal server upgrade
procedures. Query-count and payload evidence is captured in the focused tests through
`[:nixstasis, :repo, :query]` telemetry and external-term measurements. Operators should narrow
searches or policy selections when explicit result or resolution limits are reached.

## Reference and Contracts

- [Server Devices](../../modules/server-devices.md)
- [Server Web](../../modules/server-web.md)
- [Server Scripts](../../modules/server-scripts.md)
- [Script Workbench](../../operations/script-workbench.md)
- [Server Reporting](../../modules/server-reporting.md)
- [Command Policies](../../operations/command-policies.md)
- [Bounded catalog query evidence](query-evidence.md)

## Validation Evidence

- `MIX_ENV=test mix test` — 713 tests, 0 failures.
- `MIX_ENV=test mix test test/nixstasis/bounded_catalog_query_evidence_test.exs test/nixstasis_web/bounded_catalog_live_evidence_test.exs` — 8 tests, 0 failures.
- `mise exec -- mix compile --no-optional-deps --warnings-as-errors` — passed.
- `mise exec -- mix ash.codegen --check` — passed.
- `uv run scripts/check-docs.py` — passed.
- Pre-commit hooks, including formatting, docs build, markdown lint, and diff checks — passed.

## Design Reconciliation

### Delivered as Designed

All five implementation children delivered their reviewed scope: device picker and retry bounds,
canonical alert rules, report pagination, policy/catalog preflight bounds, and final index/query
measurement evidence.

### Intentional Changes

- `/alerts/rules` is the sole rule-management route; the duplicate implementation was removed.
- Query evidence is a durable feature artifact because the final acceptance contract requires
  measured query counts, returned rows, payload sizes, and query-plan evidence.
- Alert ordering uses `(product_name, id)`, matching the final deterministic default order.

### Deferred Work

No feature-scope work is deferred. Broader pagination abstractions and future group/bulk script
targeting remain outside this feature's non-goals.

### Rejected or Removed Scope

The implementation does not silently truncate policy resolutions, device selections, report rows, or
alert-rule rows, and does not introduce speculative policy/catalog indexes.

## Documentation Updated

- `docs/src/README.md`
- `docs/src/modules/server-devices.md`
- `docs/src/modules/server-web.md`
- `docs/src/modules/server-scripts.md`
- `docs/src/modules/server-monitoring.md`
- `docs/src/modules/server-reporting.md`
- `docs/src/operations/script-workbench.md`
- `docs/src/operations/command-policies.md`
- `docs/src/features/bounded-liveview-catalog-reads/query-evidence.md`
- `docs/src/features/index.md`
- `docs/src/SUMMARY.md`
- `docs/src/planned-features.md`

## Audit Trail

- Design boundary and reconciled specification: `f1345ed`.
- Policy resolution implementation: `d420a239`.
- Report pagination implementation: `8371d1b7`.
- Alert-rule catalog implementation: `42c21734`.
- Device picker and retry implementation: `05b7e8b`'s predecessor `2b08e70`.
- Index and query evidence implementation: `05b7e8b`.
- Child beads `nixstasis-mol-594.1` through `.5` are closed with independent review evidence;
  `.5` review explicitly approved after actual-path evidence tests resolved `EVIDENCE-CATALOG-001`.
