# Schema-Driven Builder Dropdowns

## References

- Beads feature root: `nixstasis-yju`
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

## Test Coverage

- `packages/server/test/nixstasis/schema_options_test.exs` and `packages/server/test/nixstasis/schema_options/`
  (`builder_contract_test.exs`, `normalizer_test.exs`, `validator_test.exs`): schema option normalization,
  validation, canonical identity, conflict handling, and bounded loading.
- `packages/server/test/nixstasis/devices/schema_validator_test.exs`: device schema registration limits.
- `packages/server/test/nixstasis_web/controllers/builder_schema_controller_test.exs`,
  `builder_config_validation_controller_test.exs`, `builder_contract_json_api_test.exs`, and
  `report_result_controller_test.exs`: generated Ash builder actions and `/api/v1` compatibility wrappers.
- `packages/server/test/nixstasis/reporting/query_builder_test.exs`: selected-schema and all-schema report scoping and
  empty-row handling.
- `packages/server/test/nixstasis/monitoring/` alert rule tests and
  `packages/server/test/nixstasis/monitoring/telemetry_seed_test.exs`: alert builder behavior and development seed
  idempotency.
- `packages/server/test/nixstasis_web/live/alerts_live_test.exs` and
  `packages/server/test/nixstasis_web/live/reports_live_test.exs`: builder dropdowns, scope changes, invalidation,
  and fail-closed saves.
- `mix ash.codegen --check` and `mix precommit` in `packages/server`.
- Manual dev-lab check: `mise run deploy:dev:seed` is idempotent across repeated runs and repairs partial telemetry
  batches.

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
