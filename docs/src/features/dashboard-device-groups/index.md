# Dashboard Device Groups

## Delivery Summary

- Beads feature root: `nixstasis-vpu`
- Status: implemented and validated for fast-forward delivery
- Pull request: not created; direct fast-forward delivery requested
- Merge commit: not applicable to fast-forward delivery; the target is recorded in Beads delivery evidence
- Design record: [design.md](design.md)

## Delivered Capability

Operators can organize devices into manual, many-to-many groups from the existing Devices view. The server owns group metadata, archive state, memberships, scoped reads, atomic mutations, and audit events without changing device identity or runtime behavior.

## User-Facing Behavior

Unscoped device managers can create, edit, archive, restore, and permanently delete group metadata. Permanent deletion requires an archived group with no memberships, while archive and restore preserve membership history. Group names are case-insensitively unique across active and archived records.

Managers can add or remove selected authorized devices through the existing bulk-action workflow. Membership changes are idempotent and transactional. Scoped operators see only groups containing accessible devices, and every displayed count includes accessible devices only. View-only operators cannot invoke mutation handlers.

The `group_id` route parameter composes with product, account number, IPv4 address, approval, connectivity, search, and sort state. Active chips show the group name. Invalid, archived, deleted, and unauthorized IDs share one non-disclosing unavailable state. Desktop rows show deterministic compact membership summaries; small screens omit that dense column while preserving the primary device workflow.

## Design Integration

`Nixstasis.Devices` remains the context boundary over Ash/PostgreSQL resources. `DeviceGroup` and `DeviceGroupMembership` extend the existing device domain rather than creating another service or public API. Trusted browser permissions construct `GroupAuthorization`, and server-side checks run again for every read or mutation.

Successful transactions emit structured audit events separately from payload-free LiveView invalidation. Device registration, approval, heartbeat, remote access, command delivery, and API-token contracts remain unchanged.

## Operational Impact

Deployment runs the named Ash migration that creates empty group and membership tables. No backfill or client upgrade is required. Before group data exists, rollback may remove the new empty tables; after operators create data, prefer a forward fix or export and restore the group tables rather than destructive rollback.

Structured group audit events follow deployment log retention. They are not persisted in a dedicated audit table. Operators manage conflicts, stale authorization, and unavailable route filters using the standalone [Device Groups](../../operations/device-groups.md) guide.

## Reference and Contracts

- [Device Groups](../../operations/device-groups.md)
- [Architecture Overview](../../architecture.md)
- [Server Devices](../../modules/server-devices.md)
- [Introduction](../../README.md)

No public HTTP API, client command, configuration setting, or device runtime contract was added.

## Validation Evidence

- Full server precommit: 528 tests, 0 failures.
- Focused device-group, device-context, permission, and Device LiveView tests passed.
- `mix ash.codegen --check`, `mix format --check-formatted`, and `mix credo --strict` passed.
- Strict documentation validation passed with 0 errors and 16 historical legacy-design warnings.
- mdBook, changed-file Rumdl, table formatting, contextlint, and repository hooks passed.
- Headed Playwright checks verified keyboard interaction, desktop summaries, preserved route state, and a usable 390-by-844 layout with the summary column omitted.
- The cold repository-wide check remains limited by the pre-existing Markdown debt tracked in `nixstasis-63w`; feature-specific and changed-file gates pass.

## Design Reconciliation

### Delivered as Designed

The feature delivered the reviewed resource lifecycle, trusted authorization, scoped visibility and counts, atomic memberships, structured audit events, payload-free refreshes, metadata and membership UI, route filtering, responsive summaries, and reader documentation.

### Intentional Changes

The implementation uses a focused inline Devices panel and native confirmation region instead of introducing a separate route or modal subsystem. Responsive presentation omits the membership summary column on small screens and keeps detailed scoped counts in the group panel.

### Deferred Work

Dynamic and nested groups, per-group role inheritance, public API exposure, feature-specific telemetry, and durable database-backed audit history remain deferred to separately designed work. Published server dependency advisories discovered during implementation are tracked by `nixstasis-9eh` and are not caused by this feature.

### Rejected or Removed Scope

The feature does not infer membership, change device runtime identity, expose inaccessible organization metadata, add client behavior, or make hard deletion the normal removal path.

## Documentation Updated

- `docs/src/README.md`
- `docs/src/architecture.md`
- `docs/src/modules/server-devices.md`
- `docs/src/operations/device-groups.md`
- `docs/src/SUMMARY.md`
- `docs/src/features/index.md`
- `docs/src/planned-features.md`
- `docs/src/features/dashboard-device-groups/index.md`

## Audit Trail

The reviewed design was committed in `eb83cb5`. Implementation was delivered through bounded commits `b18d9dd`, `5fd127c`, `6767076`, `9145338`, `b0c0d48`, `7258336`, `a5adc17`, and `8a36dd3`. Every child received an isolated read-only review and fix verification before closure. Commit `f6f8a0f` preserves implementation closure evidence in the append-only Beads interaction history.

The implementation coordinator `nixstasis-vpu.7` closed after all eight children passed acceptance. Close-out documentation, validation, delivery review, drift review, and final fast-forward evidence remain recorded on lifecycle tasks `nixstasis-vpu.8` through `nixstasis-vpu.12`.
