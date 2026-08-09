# Design — Bounded LiveView catalog reads

## Metadata

- Beads feature root: `nixstasis-mol-iuv`
- Feature slug: `bounded-liveview-catalog-reads`
- Design path: `docs/src/features/bounded-liveview-catalog-reads/design.md`
- Implemented record: `docs/src/features/bounded-liveview-catalog-reads/index.md`
- Base branch: `dev`
- Status: delivered

## Feature Summary

Bound every large LiveView/browser catalog read that can currently materialize an entire device, alert-rule, report, or command-policy catalog. Replace full-table loads with authorization-aware SQL filtering, bounded result pages or search results, narrow field selection, explicit selection/resolution limits, and a single canonical alert-rule workflow.

## User Intent

The original review found browser and LiveView memory risks caused by unbounded collection reads. The user wants the remaining findings addressed through the planning workflow, with the best UI/UX rather than a silent hard cap. The user explicitly rejected treating any route or implementation as "legacy" because Nixstasis is unreleased: the duplicate `/alerts/rules` surface must become the canonical rules route, and the duplicate implementation should be removed.

The user accepted these UX decisions:

- Script target devices use search-first, server-bounded results; selected devices remain selected across searches and pages.
- Alert rules and report definitions use server-side pagination with preserved filters and sorting.
- Command-policy previews scope reads in SQL and fail explicitly when resolution is too large; they never silently truncate commands.
- Script target selection is capped at 250 devices, matching the existing bounded collection convention, with an explicit error when the cap is exceeded.
- `/alerts/rules` is canonical; `/alerts` is the active-alert surface.

## Goals

- Remove full device-table materialization from the script workbench.
- Keep the script target picker useful for large fleets with debounced search, authorization filtering, stable selection, and clear limits.
- Make `/alerts/rules` the single schema-aware, searchable, sortable, paginated rule-management surface.
- Bound report-index reads while preserving URL state, saved preferences, filters, sorting, edit, and delete flows.
- Make command-policy resolution load only selected entries/categories and required fields, with an explicit 2,500 resolved-command guard.
- Add only indexes supported by the final SQL predicates and ordering.
- Provide tests and query/load evidence that demonstrate bounded rows, payloads, and LiveView state.

## Non-Goals

- Redesigning alert evaluation, report execution, script validation, command-policy semantics, or authorization policy.
- Introducing a generic pagination framework for every LiveView.
- Adding group/bulk targeting to the script workbench; that may be a future feature.
- Silently truncating device selections, command-policy resolutions, rule rows, or report rows.
- Exposing new public API contracts for these LiveView-only workflows.
- Changing telemetry retention or the already-delivered lifecycle-hook cleanup.

## User-Facing Behavior

### Script target devices

The test and deployment tabs show a search-first picker. A query returns at most 50 authorized devices, ordered deterministically by product name and MAC address. Search is normalized and applied in SQL across the existing device-identifying fields. Selection is represented by IDs plus separately loaded compact labels, so changing the query does not clear selected devices or require the full fleet in the socket.

Selected devices remain visible as chips or a selected summary even when they are not in the current result page. The count is shown. A user may select at most 250 devices; selecting a 251st device is rejected with an actionable message and no partial state change. The same cap is enforced by `Nixstasis.Scripts.queue_test_run/4` and `queue_deployment/4`, so non-UI callers cannot bypass it. Queueing, deployment, and retry reload the selected or historical target IDs through bounded, authorization-scoped queries rather than assuming every target is present in the current search result. Script history rows expose a SQL-derived target count instead of materializing complete historical target ID arrays; retry checks that count before loading IDs. Historical runs over the new cap remain readable but retry fails all-or-none with an explicit narrowing message.

### Alert rules

`/alerts` shows active alerts only. `/alerts/rules` shows the modern schema-aware rule table and editor. Rule search, sort, and page selection are encoded in the URL and executed in SQL before materialization, with 50 rows per page and accessible range/empty states. Rule creation and editing use nested canonical rule routes under `/alerts/rules`; the duplicate `AlertLive.Rules` implementation and tab-query route behavior are removed. Existing schema conflict handling, field/operator validation, modal accessibility, authorization, save, edit, and delete semantics remain intact.

### Reports

The `/reports` index keeps its current name/field filters, sort controls, saved view preferences, edit/delete flow, and compact report summaries. It loads one 50-row page at a time from SQL. Index rows contain only bounded summary data: identity/timestamps, field count, and at most 25 truncated field labels/paths. Full report config is loaded only on detail/edit. Filter changes reset to page one; invalid or out-of-range pages recover to a valid page. The UI reports the current range and provides accessible pagination without requiring every report definition/config in the LiveView.

### Command-policy resolution

Preview and assignment paths resolve only requested command-entry and category IDs in SQL. Manual allowlist entries, category memberships, catalog commands, and catalog-category expansion all use requested-ID/category predicates and narrow selects; `Nixstasis.CommandCatalog.Resolver.preview/1` must scope selected devices and catalog commands rather than loading whole tables. The resolver selects only the name, command path, version, source kind, and source ID required for conflict/provenance output. Additive category semantics remain unchanged. SQL preflight rejects either more than 2,500 distinct resolved command names or more than 10,000 source rows before materialization. The resolver returns an explicit over-limit error; no partial policy is previewed or queued. The LiveView explains that the operator must narrow the selected entries/categories.

## Requirements

### Functional Requirements

1. Every target collection query has a SQL-level filter/scope, deterministic order, and finite limit before loading results.
2. Authorization filters are applied in SQL wherever the resource/query boundary supports them; in-memory checks remain defense-in-depth.
3. Selected script device IDs persist across search changes and are revalidated before queue/retry side effects. Script history target counts are computed in SQL, and historical IDs are loaded only after an in-bound retry preflight.
4. `/alerts/rules` is the only rule-management UI; duplicate route/module behavior is removed rather than preserved as a compatibility surface.
5. Rule and report pagination/filter state is URL-addressable and stable across LiveView patches.
6. Command-policy resolution is exact within its explicit bound and fails closed above it.
7. Existing feature semantics, audit behavior, command delivery, report query behavior, and schema-aware validation remain compatible within the new bounded UX.

### Quality Requirements

- No unbounded catalog is assigned to a LiveView or rendered into browser HTML.
- Queries select only fields needed by the relevant UI or resolver.
- Browser diffs remain bounded when filters, pages, PubSub updates, or validation events repeat.
- Focused tests cover authorization, boundaries, empty states, stale pages, selection persistence, and over-limit errors.
- Query-plan or load evidence demonstrates bounded row counts, source rows, report summaries, and materialized payload sizes.
- UI states are keyboard accessible, announce errors, and work on narrow screens.

### Compatibility and Migration Requirements

- Nixstasis is unreleased; no legacy route or implementation compatibility is required.
- Existing `/alerts` active-alert behavior remains available.
- Existing script queue/retry records and report preference keys remain readable.
- Existing command-policy assignments remain readable and deliverable; only new previews/queues enforce the explicit resolution guard.
- No data migration is expected unless final query indexes require one.

## Existing Context

The prior performance work fixed CodeMirror and terminal cleanup, bounded script history and payload reads, scoped/limited command-policy LiveView collections, bounded active alerts/devices, added query indexes, and added configurable telemetry retention. The remaining static findings are:

- `packages/server/lib/nixstasis_web/live/script_live/show.ex` loads `Devices.list_devices/0` and renders the collection in both target tabs.
- `packages/server/lib/nixstasis_web/live/alerts/index_live.ex` loads all rules and filters/sorts them in memory; `alerts/rules_live.ex` is a duplicate route implementation.
- `packages/server/lib/nixstasis/reporting.ex` materializes every custom report/config for the report index.
- `packages/server/lib/nixstasis/command_allowlists/policy_resolver.ex` loads all command entries and join rows before filtering selected IDs/categories.
- `packages/server/lib/nixstasis/command_catalog/resolver.ex` and the command-policy LiveView expand selected catalog devices/categories from bounded or full in-memory collections.

Established bounded patterns include `@collection_limit 250`, 50-row script histories, SQL-scoped Ash queries, narrow `Ash.Query.select/1`, authorized device ID filtering, and the existing URL-backed report preference state.

## Proposed Design

### Ownership

- `Nixstasis.Devices` owns compact, authorization-scoped script target search and selected-target reload helpers.
- `Nixstasis.Scripts` owns bounded history target counts and retry preflight before loading historical IDs.
- `ScriptLive.Show` owns search state, selected ID state, 250-selection UX, and target-picker rendering.
- `AlertLive.Index` owns the canonical `/alerts/rules` table/editor and SQL-backed rule page state.
- `Nixstasis.Reporting` and `ReportLive.Index` own bounded report index query/state behavior.
- `Nixstasis.CommandAllowlists.PolicyResolver` and `Nixstasis.CommandCatalog.Resolver` own SQL-scoped exact resolution, source-row preflight, and the 2,500-command guard; the command-policy LiveView renders their errors and does not expand categories from truncated lists.
- A named migration owns only indexes justified by final query predicates.

### Query and state contracts

- Picker result limit: 50 devices per query.
- Picker selection limit: 250 authorized device IDs.
- Script history target count is SQL-derived; full target ID arrays are not assigned to the LiveView before retry preflight.
- Rule page size: 50 rows.
- Report page size: 50 rows.
- Command-policy resolution limit: 2,500 distinct resolved command names.
- Command-policy source-row preflight limit: 10,000 manual/catalog membership rows.
- Report index summary limit: 25 field labels/paths per report, with bounded string lengths; full config is detail-only.
- All IDs are normalized and authorization-checked at the side-effect boundary.
- Empty searches return the first deterministic page, not the complete collection.
- Query errors produce recoverable UI errors and do not mutate selection or queue state.

### Canonical alert routes

Use one modern LiveView module for active alerts and rules, with explicit route actions:

- `/alerts` — active alerts.
- `/alerts/rules` — rule index.
- `/alerts/rules/new` — create rule.
- `/alerts/rules/:id/edit` — edit rule.

Remove the separate `AlertLive.Rules` module and the old tab-query route behavior. Update links, tests, and docs together.

### Index strategy

Do not add indexes until the final queries are established. Candidate indexes must support deterministic device picker ordering/search, rule product/name/status/order predicates, report name/order predicates, and command-policy join lookups. JSONB field filters receive an index only when the final SQL expression can use it; a generic GIN index is not assumed to accelerate `jsonb_array_elements` scans.

### Observability

Focused load tests record query count, returned rows, selected fields, page boundaries, and materialized payload size. Existing telemetry conventions may receive bounded-read measurements, but no new high-cardinality labels or per-user payload logging is allowed.

## Architecture Consistency

### Existing Patterns Reused

- Ash query filters, limits, sorting, and narrow selects.
- `Permissions.authorized_device_ids/1` and trusted device scope.
- URL-backed LiveView filter/sort preference state.
- Existing table/pagination component conventions where available.
- Existing command-policy preview and audit boundaries.

### Invariants Preserved

- Device authorization is enforced before queueing or retrying.
- Alert rules fail closed on schema conflicts and preserve validation semantics.
- Reports remain scoped to their existing schema/filter behavior.
- Command policies are additive, deny-by-default, and never partially applied.
- Browser state and server-side queue state remain separate authorities.

### New Decisions Introduced

- Search-first target picker with 50-result pages and a 250-device selection cap.
- Canonical explicit alert-rule routes under `/alerts/rules`; no legacy duplicate route/module.
- 50-row server-side pages for alert rules and reports.
- Explicit 2,500-command command-policy resolution guard with user-visible failure.
- Query/index evidence is part of acceptance, not an optional post-hoc benchmark.

### Architecture Documentation Changes

Update the existing module pages named below; no new architecture page is needed.

## Operational Considerations

Operators will see bounded, searchable pages rather than an entire catalog. Large command-policy categories may require narrowing before preview or assignment. Query/load evidence should be retained with validation artifacts so future catalog growth can be evaluated. No runtime configuration is required for the initial limits; changes to limits are code/design changes and must preserve bounded behavior.

## Documentation Impact

| Documentation concern      | Exact page                                                  | Create or update        | Planned change                                                                                           | Owning Beads task                             |
|----------------------------|-------------------------------------------------------------|-------------------------|----------------------------------------------------------------------------------------------------------|-----------------------------------------------|
| Architecture               | `docs/src/modules/server-devices.md`                        | Update                  | Document compact authorized script-target reads and selected-target reload ownership.                    | `nixstasis-mol-594.1`                         |
| Architecture               | `docs/src/modules/server-web.md`                            | Update                  | Document canonical `/alerts/rules` routes and bounded LiveView collection behavior.                      | `nixstasis-mol-594.2` / `nixstasis-mol-594.4` |
| Architecture               | `docs/src/README.md`                                        | Update                  | Update route/module inventory for canonical `/alerts/rules` and removed duplicate module.                | `nixstasis-mol-594.2`                         |
| Architecture               | `docs/src/modules/server-monitoring.md`                     | Update                  | Document the single rule-management surface and SQL-backed rule paging.                                  | `nixstasis-mol-594.2`                         |
| Architecture               | `docs/src/modules/server-scripts.md`                        | Update                  | Document search-first target selection, selection cap, and bounded retry/queue reads.                    | `nixstasis-mol-594.1`                         |
| Usage / Operations         | `docs/src/operations/script-workbench.md`                   | Update                  | Document search-first target selection, selected-device persistence, 250-device cap, and retry behavior. | `nixstasis-mol-594.1`                         |
| Architecture               | `docs/src/modules/server-reporting.md`                      | Update                  | Document report-index pagination, URL state, and bounded config materialization.                         | `nixstasis-mol-594.3`                         |
| Usage / Operations         | `docs/src/operations/command-policies.md`                   | Update                  | Document over-limit policy previews and operator narrowing guidance.                                     | `nixstasis-mol-594.4`                         |
| Navigation                 | `docs/src/SUMMARY.md`                                       | Update                  | Register the implemented feature record alongside the existing design record.                            | `nixstasis-mol-8bs`                           |
| Implemented Feature Record | `docs/src/features/bounded-liveview-catalog-reads/index.md` | Create during close-out | Preserve delivery and audit history.                                                                     | `nixstasis-mol-8bs`                           |

## Validation Strategy

- Focused LiveView tests for scripts, alerts, reports, and command policies.
- Context/resolver tests for authorization-scoped SQL reads, limits, selected fields, and over-limit behavior.
- Query-plan/load evidence with representative large catalogs, including 10,000 devices, rules, reports, and command-policy joins where test setup permits.
- `mix test` focused files, then full `mix precommit` after review fixes stabilize.
- `mix compile --no-optional-deps --warnings-as-errors`.
- `mix ash.codegen --check`.
- `MIX_ENV=test mix ecto.migrate` and migration/index checks.
- `uv run scripts/check-docs.py` and `git diff --check`.
- Browser smoke checks for search, selection persistence, pagination, canonical alert routes, empty states, and over-limit errors.
- Verify no full-catalog assigns or template loops remain via targeted source searches and query logs.

## Implementation Decomposition

The implementation coordinator `nixstasis-mol-594` owns five parallel-first bounded tasks:

1. `nixstasis-mol-594.1` — search-first script target picker and selected-target reloads.
2. `nixstasis-mol-594.2` — canonical `/alerts/rules` consolidation and paged rules.
3. `nixstasis-mol-594.3` — paged report index.
4. `nixstasis-mol-594.4` — SQL-scoped manual/catalog command-policy resolution, compatibility preview, category expansion, and over-limit guards.
5. `nixstasis-mol-594.5` — final query indexes and measurement after query shapes stabilize.

Tasks 1–4 can proceed independently after specification reconciliation. Task 5 is blocked by tasks 1–4 and depends on their final query shapes. All implementation work is gated by the lifecycle specification reconciliation through the implementation coordinator.

## Dependencies and Parallelism

- The four surface tasks are independent and can be reviewed separately.
- Query-index work follows the surface query shapes and should not introduce speculative indexes.
- Close-out documentation and validation wait for all implementation tasks.
- No external service or schema migration is required unless justified by final query plans.

## Rollout and Migration

This is unreleased software. Replace duplicate alert routes/modules directly; no backwards-compatibility redirect is required. Deploy code and any named indexes together through the normal migration path. Existing report preferences, script run records, and command-policy assignments remain readable.

## Risks and Tradeoffs

- Pagination adds a query and interaction step but prevents large LiveView diffs.
- Search-first device selection is more scalable but requires clear selection persistence and selected-label handling.
- A 250-device cap prevents accidental fleet-wide queue storms but makes future group targeting more valuable.
- A 2,500-command or 10,000-source-row guard may reject legitimate large categories; explicit failure is safer than silently issuing an incomplete policy.
- Counts and JSONB field searches can remain expensive; query evidence must confirm plans rather than assuming an index helps.

## Rejected Alternatives

- Loading all devices/rules/reports and filtering in Elixir: rejected because it materializes unbounded rows and payloads.
- A hard page-size cap with no search or pagination: rejected because it hides records and harms discoverability.
- Silently truncating command-policy category expansion: rejected because it changes security policy semantics.
- Keeping `/alerts/rules` as a separate "legacy" implementation: rejected because the project is unreleased and duplicate behavior increases drift.
- Building a generic pagination abstraction first: rejected as unnecessary scope; each surface has distinct authorization and state requirements.

## Open Questions

None blocking implementation. Query-plan details and exact index definitions are implementation evidence, not product-policy decisions.

## Deferred Decisions

- Group/bulk targeting beyond 250 explicit script devices is a separate future feature.
- Runtime-configurable page sizes are not needed initially; fixed bounded defaults remain part of the feature contract.

## Planning Record

### Questions Asked and Answers

- User requested `/skill:plan-features` planning for the remaining unbounded LiveView and resolver reads.
- Recommended UX was search-first device selection, paginated rule/report tables, SQL-scoped command resolution, and explicit over-limit errors; user accepted.
- User rejected retaining anything categorized as legacy because the software is unreleased.
- User selected `/alerts/rules` as the canonical rules route in place of `/alerts?tab=rules`.
- User accepted the recommended 250-device selection cap after context about socket, authorization, and queue bounds.

### Assumptions

- Existing permissions and route authorization remain authoritative.
- The current 250 collection convention is an acceptable initial explicit-device selection limit.
- Existing report preference keys can carry page/filter state without a compatibility migration.
- A 2,500 resolved-command bound is acceptable as the initial safe policy-preview boundary because the user accepted explicit failure rather than truncation; adjust only through a reviewed design change.

### Design Changes During Planning

- Initial scope included a separate legacy `/alerts/rules` surface; user directed that no legacy surface be retained.
- Canonical rule URL changed from tab query state to explicit `/alerts/rules` routes.
- Device picker design gained a 250 selected-device cap after discussing why search limits alone do not bound socket/queue state.

### Source Material

- `packages/server/lib/nixstasis_web/live/script_live/show.ex`
- `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- `packages/server/lib/nixstasis_web/live/alerts/rules_live.ex`
- `packages/server/lib/nixstasis/reporting.ex`
- `packages/server/lib/nixstasis_web/live/reports/index_live.ex`
- `packages/server/lib/nixstasis/command_allowlists/policy_resolver.ex`
- `packages/server/lib/nixstasis_web/live/command_policy_live/index.ex`
- `packages/server/lib/nixstasis/command_catalog/resolver.ex`
- `docs/src/modules/server-web.md`
- `docs/src/modules/server-devices.md`
- `docs/src/modules/server-scripts.md`
- `docs/src/modules/server-reporting.md`
- `docs/src/modules/server-monitoring.md`
- `docs/src/operations/command-policies.md`
- Prior commits: `c8be60df`, `faaa7c84`, `52fbc2d`, `ebde27a8`, `97d57232`, `30d89b5d`, `4b0eaad2`, `3aab000a`, `688f0118`
