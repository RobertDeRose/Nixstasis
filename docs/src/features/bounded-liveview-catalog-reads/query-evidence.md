# Bounded catalog query evidence

This record accompanies task `nixstasis-mol-594.5`. It records the migration, query-plan, and
bounded-materialization evidence for the final LiveView catalog query shapes. The application
queries apply authorization and filters before these limits; this evidence verifies the final
ordering/limit shape and the focused regression suites verify authorization and UI behavior.

## Validation commands

Run from `packages/server`:

```text
mise exec -- mix format --check-formatted priv/repo/migrations/20260809010000_add_bounded_catalog_order_indexes.exs
# rc 0
mise exec -- mix compile --no-optional-deps --warnings-as-errors
# rc 0
mise exec -- mix ash.codegen --check
# rc 0
MIX_ENV=test mix ecto.migrations
# rc 0; 20260809010000_add_bounded_catalog_order_indexes is up
```

The focused feature suites recorded 95 passing tests with zero failures before the index-only
change. `bounded_catalog_query_evidence_test.exs` adds executable query-count, returned-row,
payload-byte, actual preview, source-row rejection, and installed-index assertions;
`bounded_catalog_live_evidence_test.exs` measures the actual alert-rule LiveView. They cover the bounded picker, alert-rule page, report page, manual/catalog policy
preflights, narrow projections, authorization, and over-limit failures.

## Rows, queries, and materialized payloads

| Surface                | SQL row bound / returned rows asserted                                                                                                                                  | Query count evidence                                                                                                                                                                                                                                                                                                                                                                              | Materialized payload evidence                                                                                                                                                                                                                   |
|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Device picker          | `script_live_test.exs` creates 51 authorized devices and asserts exactly 50 rendered device IDs; picker search is SQL-scoped and selected labels are reloaded narrowly. | `bounded_catalog_query_evidence_test.exs` calls `Devices.list_devices/1`, records 1 query, 50 rows, and 157,699 external-term bytes; the existing devices test also covers one-query authorization scoping.                                                                                                                                                                                       | Picker projection is `id`, `product_name`, and `mac_address`; the test asserts no 51st row is rendered and selected labels remain bounded across searches.                                                                                      |
| Alert rules            | `alerts_live_test.exs` creates 51 rules and asserts page 2 contains only row 51, reports `51–51 of 51`, and redirects invalid page 99 to page 2.                        | `bounded_catalog_live_evidence_test.exs` calls the actual `/alerts/rules` LiveView and records 8 repo queries, 50 rendered rules, and 66,253 external-term HTML bytes. The pagination suite separately exercises count/page paths.                                                                                                                                                                | The rule page selects the displayed identity/condition fields only; page HTML contains one 50-row page, never the full 51-row catalog.                                                                                                          |
| Reports                | `custom_report_list_test.exs` creates 55 reports and asserts page lengths 50, 5, and 0; repeated page 1 IDs are identical.                                              | `bounded_catalog_query_evidence_test.exs` calls `Reporting.list_custom_reports_with_view/1` and records 1 query, 50 rows, and 14,352 external-term bytes; the pagination suite exercises separate count/page calls and no full config on index rows.                                                                                                                                              | Index rows contain identity/timestamps, field count, and at most 25 summary labels. The test asserts the bounded summary and loads full config only in edit/detail paths.                                                                       |
| Manual policy preview  | Resolver tests exercise selected-entry/category scoping and the 10,000 source-row / 2,500 distinct-command preflight.                                                   | `bounded_catalog_query_evidence_test.exs` calls both actual preview functions: manual preview records 5 queries, 544 external-term bytes; catalog preview records 6 queries, 181 bytes. Actual manual and catalog preflight calls each insert 10,001 rows, return the source-row-limit error, and materialize only 92 external-term bytes; resolver tests assert no partial preview/queue result. | Narrow entry/source projections and explicit bound errors prevent oversized materialized payloads; actual accepted manual preview measured 544 bytes and rejected manual preflight measured 92 bytes.                                           |
| Catalog policy preview | Catalog resolver tests exercise selected command/category/device scoping, mapping joins, and the 2,500 distinct-command guard.                                          | The actual catalog preview records 6 repo queries; the 10,001-row preflight records 5 queries before the source-row error, and no selected command/mapping/device/snapshot payload is loaded after rejection.                                                                                                                                                                                     | Selected command/mapping/device/snapshot fields are narrow; actual accepted catalog preview measured 181 bytes and rejected catalog preflight measured 92 bytes, while over-limit tests assert an explicit error rather than a partial payload. |

These are regression assertions rather than a benchmark: they prove the returned-row and
materialization ceilings that protect socket/browser memory. Query telemetry remains available
through the `[:nixstasis, :repo, :query]` event used by the device query-count test.

## Index and query-plan evidence

`MIX_ENV=test mix ecto.migrations` reported the new migration up. The resulting indexes are:

- `devices_picker_product_mac_id_index` on `(product_name, mac_address, id)`;
- `alert_rules_catalog_product_id_index` on `(product_name, id)`;
- `custom_reports_lower_name_id_index` on `(lower(name), id)`.

The reviewer ran `EXPLAIN` for each bounded `ORDER BY ... LIMIT 50` shape. With the normal
cost-based planner and the small test database, PostgreSQL selected sequential scans; with
`enable_seqscan=off` (the migration/index coverage check), each plan selected its matching
index and retained `Limit` above the scan:

```text
devices:  Limit -> Index Scan using devices_picker_product_mac_id_index
alerts:   Limit -> Index Scan using alert_rules_catalog_product_id_index
reports:  Limit -> Index Scan using custom_reports_lower_name_id_index
```

Existing primary-key, foreign-key, array-GIN, JSONB-GIN, and join indexes cover command-policy
and catalog compatibility lookups; no speculative policy/catalog index was added. The migration
has explicit reversible `down/0` operations for all three new indexes.
