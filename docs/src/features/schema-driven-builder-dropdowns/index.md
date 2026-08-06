# Schema-Driven Builder Dropdowns

## Delivery Summary

- Beads feature root: `nixstasis-yju`
- Status: delivered
- Pull request: not created; merge was explicitly selected
- Merge commit: `24999c01f811ebaf7c3de3b3344bac2689012367` (fast-forward delivery)
- Design record: [design.md](design.md)

## Delivered Capability

Alert rules and custom reports now populate field selectors from device-advertised
schema metadata. Schema identity is the `(product_name, schema_version)` pair;
selected schema scopes are explicit, and all-schema/all-version report scopes
retain their cross-schema behavior.

The builders normalize schema properties into selectable labels and value types,
clear selections that become invalid after a scope change, and block saves when a
schema is missing, unavailable, conflicting, or stale. Report results constrain
selected schema scopes to matching devices, omit all-empty telemetry rows, and
return no rows for reports with no valid telemetry paths.

## User-Facing Behavior

- Alert and report field dropdowns expose available schema fields instead of
  requiring free-form paths.
- Selecting a product and version refreshes fields and typed filter controls;
  selecting all versions preserves an explicit all-version scope.
- Conflicting definitions for one product/version show a blocking explanation
  and never select an arbitrary device definition.
- Missing or unavailable schema options show recovery guidance and keep Save
  disabled.
- All-schema report fields merge compatible definitions and use generic string
  handling when contributing types disagree.
- Report list filtering, sorting, pagination, empty-result messaging, and
  authorization remain intact.

## Design Integration

`Nixstasis.Devices` owns canonical schema identity and conflict detection.
`Nixstasis.SchemaOptions` owns normalization, validation, and measured option
loading. Single explicit schema scopes use bounded direct lookup; multi-reference
report scopes use one database batch returning one canonical row per identity.
Report LiveViews retain normalized options and derive display collections rather
than storing duplicate option lists and maps in the socket. Builder LiveViews load
at most 128 schema references; an oversized catalog fails closed with guidance
instead of retaining an unbounded reference list.

The existing generated Ash builder actions and `/api/v1` compatibility wrappers
remain the external contract. Existing report-view authorization remains the
boundary for builder access; this feature does not add per-device schema ACLs.

## Operational Impact

Use the Compose development seed task after the dev lab is running:

```sh
mise run deploy:dev:seed
```

The task seeds stable offline schema-builder devices, telemetry, an alert, and a
report through Compose. It performs bounded per-sample existence checks,
serializes marked telemetry writes per seed marker, repairs partial telemetry
batches, and preserves idempotency without loading the full telemetry table.
Database-only fixtures do not provide SSH or FRP routes; use a
real Compose client for remote-access testing.

The schema option service emits
`[:nixstasis, :builder, :schema_options, :load]` telemetry with measured
`duration_ms` and result metadata. Device schema registration rejects definitions
larger than 65,536 encoded bytes, deeper than 8 nested levels, or containing more
than 256 map fields. Automated timing is implementation evidence, not human
task-completion evidence.

## Reference and Contracts

- [Client-Server Interface](../../client-server-interface.md)
- [Server Monitoring](../../modules/server-monitoring.md)
- [Server Reporting](../../modules/server-reporting.md)
- [Server Web](../../modules/server-web.md)
- [Deployment Compose](../../modules/deployment-compose.md)
- [Builder API reference](../../reference/openapi/builder-api.yaml)
- [Architecture Overview](../../architecture.md)
- [Runtime Boundaries](../../runtime-boundaries.md)

The generated Ash JSON:API builder contracts and retained `/api/v1` wrappers
remain documented in the client-server interface and builder API reference.

## Validation Evidence

- Focused schema/builder/controller/alert/report tests: 108 tests, 0 failures.
- `NIXSTASIS_DB_AUTOSTART=false mise x -- mix test test/nixstasis/reporting/query_builder_test.exs`: 11 tests, 0 failures.
- `NIXSTASIS_DB_AUTOSTART=false mise x -- mix test test/nixstasis/monitoring test/nixstasis/monitoring/telemetry_seed_test.exs`: 28 tests, 0 failures.
- Final feature commit `NIXSTASIS_DB_AUTOSTART=false mise x -- mix precommit`: 642 tests, 0 failures.
- `mise run check`, `uv run scripts/check-docs.py`, `mix ash.codegen --check`, `bash -n .mise/tasks/deploy/dev/seed.sh`, and `git diff --check` passed. Repository output retained 37 non-failing mdBook lint warnings.
- The Compose server image rebuilt, `mise run deploy:dev -- up --clients 1` recreated the server, and the seed task passed first-run/repeat-run checks. After one legacy seeded event was removed through Compose RPC, the seed task reported one repaired event and the next run reported no duplicates.
- Existing LiveView missing-form-ID warnings remain non-failing diagnostics.

## Design Reconciliation

### Delivered as Designed

- Alert and report dropdowns use canonical product/version schema identities,
  independent builder state, explicit scope changes, invalidation, and
  fail-closed saves.
- Generated and compatibility builder contracts preserve their authorization,
  error, and response boundaries.
- Selected-schema report results are scoped by device product/version while
  all-schema results remain cross-schema.
- Schema option loading is measured and batched for multi-reference report
  scopes without arbitrary conflict resolution.

### Intentional Changes

- Canonical conflict detection now bounds single-identity reads and batch loads
  one canonical row per identity; divergent definitions remain unavailable.
- Report detail type aggregation and telemetry empty-row handling were tightened
  to avoid arbitrary types and blank legacy rows.
- The development seed task now checks individual stable samples, serializes
  marked writes, and repairs partial batches while retaining compatibility with the
  original batch marker.

### Deferred Work

- The 90-second alert/report task-flow target remains deferred because no valid
  operator observation window, participant sample, elapsed time, or pass/fail
  result was available. Automated tests and timings do not substitute for it.
- Broader builder redesign, cross-product schema composition, and per-device
  schema ACLs remain outside this feature.

### Rejected or Removed Scope

- Free-form field entry, silent schema-version fallback, arbitrary first-device
  selection, and merging divergent definitions remain rejected.
- No client transport migration, new SSH/FRP route, or remote database access
  was added for the development fixtures.

## Documentation Updated

- `docs/src/features/schema-driven-builder-dropdowns/index.md`
- `docs/src/features/schema-driven-builder-dropdowns/design.md`
- `docs/src/features/index.md`
- `docs/src/SUMMARY.md`
- `docs/src/planned-features.md`
- `docs/src/client-server-interface.md`
- `docs/src/modules/server-monitoring.md`
- `docs/src/modules/server-reporting.md`
- `docs/src/modules/server-web.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/development/tooling.md`
- `docs/src/reference/openapi/builder-api.yaml`
- `deploy/compose/README.md`

The interface, OpenAPI, monitoring, web, tooling, and builder reference pages
were reviewed against the delivered contracts; only the paths with required
reader-facing reconciliation changes were edited in this close-out unit.

## Audit Trail

The reviewed design and graph were established in `01e4e39` and corrected in
`16271f3`. Canonical conflict handling and option timing were delivered in
`0447221` and `429ad21`; seed fixtures and report telemetry behavior followed in
`e06ca06`, `bc71f03`, and `f291154`. Report unavailable-schema guidance,
save revalidation, version-scoped types, all-version preservation, bounded
option loading, empty projections, and bounded seed checks were delivered in
`7f4dbee`, `5f5c5d1`, `a421cabc`, `39d40ab`, `b1ea569`, `259f2cf`, and `49b70e5`.

Implementation and review findings are recorded in Beads. The implementation
coordinator `nixstasis-yju.7`, documentation `.8`, validation `.9`, and holistic
reviews `.10` and `.11` are closed with commit and validation evidence. The
feature was fast-forwarded into `dev` at
`24999c01f811ebaf7c3de3b3344bac2689012367`; no pull request was created.
