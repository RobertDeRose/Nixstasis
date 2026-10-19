# Schema-Driven Builder Dropdowns

When you build an alert rule or a custom report, the field pickers now list the fields your devices actually report,
taken from the schemas they advertise. A schema is identified by its `(product_name, schema_version)` pair. You choose a
schema explicitly, and reports that span all schemas or all versions still work across them.

The builders turn schema properties into readable labels with value types, clear any selection that stops being valid
when you change scope, and refuse to save when a schema is missing, unavailable, conflicting, or out of date. Report
results for a chosen schema only include matching devices, skip rows where every field is empty, and return nothing
for a report with no valid telemetry fields. The original plan is in the [design record](design.md).

## What changed for users

- Alert and report field dropdowns list the available fields, instead of asking you to type a path.
- Choosing a product and version refreshes the fields and the typed filter controls. Choosing all versions keeps an
  explicit all-versions scope.
- If devices report different definitions for the same product and version, you see a blocking explanation; Nixstasis
  never just picks one device's definition.
- If schema options are missing or unavailable, you see what to do about it, and **Save** stays disabled.
- In all-schema reports, fields from matching definitions are merged; when their types disagree, the field is treated
  as text.
- Report list filtering, sorting, paging, empty-result messages, and permissions work as before.

## How it fits in

`Nixstasis.Devices` decides what a schema's identity is and spots conflicts. `Nixstasis.SchemaOptions` turns schemas
into options, validates selections, and measures how long loading takes. A single chosen schema is looked up directly,
with a limit; a report covering several schemas loads them in one database query that returns one row per identity.
Report pages keep the options once and derive what they display, rather than storing several copies. Builder pages load
at most 128 schema references; a larger catalog is refused, with guidance, rather than loaded in full.

The generated Ash builder actions are the external API. Access to the
builders still follows report-view permission; there is no per-device schema access control.

## Running it

Once the development lab is running, fill it with sample data:

```sh
mise run deploy:dev:seed
```

The task creates stable offline devices for the schema builders, telemetry, an alert, and a report, through Compose.
You can run it repeatedly: it checks each sample before adding it, writes each batch of marked telemetry one at a time,
completes any half-written batch, and never loads the whole telemetry table. These database-only devices have no SSH
or FRP routes, so use a real Compose client to test remote access.

Loading schema options emits `[:nixstasis, :builder, :schema_options, :load]` telemetry, with `duration_ms` and the
result. Device registration refuses schemas larger than 65,536 encoded bytes, nested deeper than 8 levels, or with more
than 256 map fields.

## Differences from the design

- **Conflict checks are bounded.** Looking up one identity is limited, and batch loads return one row per identity. A
  schema with conflicting definitions stays unavailable.
- **Stricter report types and rows.** Report detail no longer picks a type arbitrarily, and blank rows from older
  telemetry are skipped.
- **Repeatable seeding.** The seed task checks each sample, writes marked batches one at a time, and completes partial
  batches, while still recognizing data from the original batch marker.

## Not included

- The design's 90-second target for building an alert or report was not measured with real operators. Automated tests
  and timings don't stand in for that.
- There is no broader builder redesign, no combining schemas across products, and no per-device schema access control.
- Fields can't be typed in freely. Nixstasis never falls back silently to another schema version, never picks the first
  device's definition, and never merges conflicting definitions.
- The sample data adds no client transport changes, SSH or FRP routes, or remote database access.

## Tests

- `packages/server/test/nixstasis/schema_options_test.exs` and `packages/server/test/nixstasis/schema_options/`
  (`builder_contract_test.exs`, `normalizer_test.exs`, `validator_test.exs`): turning schemas into options, validation,
  schema identity, conflicts, and bounded loading.
- `packages/server/test/nixstasis/devices/schema_validator_test.exs`: schema size limits at registration.
- `packages/server/test/nixstasis_web/controllers/builder_contract_json_api_test.exs` and
  `report_result_controller_test.exs`: the generated builder actions and report results.
- `packages/server/test/nixstasis/reporting/query_builder_test.exs`: single-schema and all-schema reports, and empty
  rows.
- The alert rule tests in `packages/server/test/nixstasis/monitoring/`, and `telemetry_seed_test.exs` there: the alert
  builder and repeatable seeding.
- `packages/server/test/nixstasis_web/live/alerts_live_test.exs` and `reports_live_test.exs`: the dropdowns, scope
  changes, clearing invalid selections, and refusing to save.
- `mix ash.codegen --check` and `mix precommit` in `packages/server`.
- Manual lab check: `mise run deploy:dev:seed` can be run repeatedly, and completes partial telemetry batches.

## Related pages

- [Client-Server Interface](../../client-server-interface.md#builder-api)
- [Server Monitoring](../../modules/server-monitoring.md)
- [Server Reporting](../../modules/server-reporting.md)
- [Server Web](../../modules/server-web.md)
- [Local Stack](../../development/local-stack.md)
- [Architecture Overview](../../architecture.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
