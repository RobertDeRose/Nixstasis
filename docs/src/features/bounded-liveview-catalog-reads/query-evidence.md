# Bounded catalog query evidence

This record describes the migration, query-plan, and bounded-materialization evidence for the final LiveView catalog
query shapes. The application queries apply authorization and filters before these limits; this evidence verifies the
final ordering/limit shape and the focused regression suites verify authorization and UI behavior.

## Validation commands

Run from `packages/server`:

```text
mise exec -- mix format --check-formatted priv/repo/migrations/20260809010000_add_bounded_catalog_order_indexes.exs
mise exec -- mix compile --no-optional-deps --warnings-as-errors
mise exec -- mix ash.codegen --check
MIX_ENV=test mix ecto.migrations
```

`MIX_ENV=test mix ecto.migrations` should list `20260809010000_add_bounded_catalog_order_indexes` as up.

`packages/server/test/nixstasis/bounded_catalog_query_evidence_test.exs` holds executable query-count, returned-row,
payload-byte, actual preview, source-row rejection, and installed-index assertions;
`packages/server/test/nixstasis_web/bounded_catalog_live_evidence_test.exs` measures the actual alert-rule LiveView.
Together with the focused catalog suites they cover the bounded picker, alert-rule page, report page, manual/catalog
policy preflights, narrow projections, authorization, and over-limit failures.

## Rows, queries, and materialized payloads

| Surface                | SQL row bound / returned rows asserted                                                                                                                                  | Query count evidence                                                                                                                                                                                                                                                                                              | Materialized payload evidence                                                                                                                                             |
|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Device picker          | `script_live_test.exs` creates 51 authorized devices and asserts exactly 50 rendered device IDs; picker search is SQL-scoped and selected labels are reloaded narrowly. | `bounded_catalog_query_evidence_test.exs` calls `Devices.list_devices/1` and asserts 1 query and 50 rows with a bounded external-term size; the existing devices test also covers one-query authorization scoping.                                                                                                | Picker projection is `id`, `product_name`, and `mac_address`; the test asserts no 51st row is rendered and selected labels remain bounded across searches.                |
| Alert rules            | `alerts_live_test.exs` creates 51 rules and asserts page 2 contains only row 51, reports `51–51 of 51`, and redirects invalid page 99 to page 2.                        | `bounded_catalog_live_evidence_test.exs` calls the actual `/alerts/rules` LiveView and asserts a bounded repo query count, 50 rendered rules, and a bounded external-term HTML size. The pagination suite separately exercises count/page paths.                                                                  | The rule page selects the displayed identity/condition fields only; page HTML contains one 50-row page, never the full 51-row catalog.                                    |
| Reports                | `custom_report_list_test.exs` creates 55 reports and asserts page lengths 50, 5, and 0; repeated page 1 IDs are identical.                                              | `bounded_catalog_query_evidence_test.exs` calls `Reporting.list_custom_reports_with_view/1` and asserts 1 query and 50 rows with a bounded external-term size; the pagination suite exercises separate count/page calls and no full config on index rows.                                                         | Index rows contain identity/timestamps, field count, and at most 25 summary labels. The test asserts the bounded summary and loads full config only in edit/detail paths. |
| Manual policy preview  | Resolver tests exercise selected-entry/category scoping and the 10,000 source-row / 2,500 distinct-command preflight.                                                   | `bounded_catalog_query_evidence_test.exs` calls both actual preview functions and asserts bounded payloads. Actual manual and catalog preflight calls each insert 10,001 rows, return the source-row-limit error, and materialize only a small error term; resolver tests assert no partial preview/queue result. | Narrow entry/source projections and explicit bound errors prevent oversized materialized payloads.                                                                        |
| Catalog policy preview | Catalog resolver tests exercise selected command/category/device scoping, mapping joins, and the 2,500 distinct-command guard.                                          | The combined 10,001-row preflight issues the manual-validation queries before the catalog resolver rejects the raw list, and no catalog command/mapping/device/snapshot payload is loaded after rejection. Direct catalog preview of an oversized raw list fails before any SQL query.                            | Selected command/mapping/device/snapshot fields are narrow; over-limit tests assert an explicit error rather than a partial payload.                                      |

These are regression assertions rather than a benchmark: they prove the returned-row and materialization ceilings that
protect socket/browser memory. Query telemetry remains available through the `[:nixstasis, :repo, :query]` event used by
the device query-count test.

## Index and query-plan evidence

The migration adds these indexes:

- `devices_picker_product_mac_id_index` on `(product_name, mac_address, id)`;
- `alert_rules_catalog_product_id_index` on `(product_name, id)`;
- `custom_reports_lower_name_id_index` on `(lower(name), id)`.

Each index matches one bounded `ORDER BY ... LIMIT 50` shape. On a small database the cost-based planner may prefer
sequential scans; to check index coverage, run `EXPLAIN` for each shape with `enable_seqscan=off`, where each plan
should select its matching index and retain `Limit` above the scan:

```text
devices:  Limit -> Index Scan using devices_picker_product_mac_id_index
alerts:   Limit -> Index Scan using alert_rules_catalog_product_id_index
reports:  Limit -> Index Scan using custom_reports_lower_name_id_index
```

Existing primary-key, foreign-key, array-GIN, JSONB-GIN, and join indexes cover command-policy and catalog compatibility
lookups; no speculative policy/catalog index was added. The migration has explicit reversible `down/0` operations for
all three new indexes.
