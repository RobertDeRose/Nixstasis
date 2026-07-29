# Design — Dashboard Device Groups

## Metadata

- Beads feature root: `nixstasis-vpu`
- Feature slug: `dashboard-device-groups`
- Design path: `docs/src/features/dashboard-device-groups/design.md`
- Implemented record: `docs/src/features/dashboard-device-groups/index.md`
- Base branch: `dev`
- Status: reviewed — implementation ready

## Feature Summary

Add manual, operator-managed device groups to the existing Devices LiveView. Groups organize devices without changing
device identity or runtime behavior, support many-to-many membership, and compose with the existing route-backed device
filters while preserving device-scoped authorization.

## User Intent

Operators need a predictable way to organize fleets beyond product and account fields. From the Devices workflow they
must be able to create and maintain groups, add or remove selected devices, understand membership, and filter the device
list without losing existing search, sort, or filters. Manual organization is intentional; this feature must not infer
membership or alter registration, approval, heartbeat, remote access, or API-token behavior.

## Goals

- Let authorized operators create, rename, describe, archive, restore, and permanently delete eligible device groups.
- Let authorized operators add or remove selected devices while allowing a device to belong to multiple groups.
- Make group membership visible without making the Devices table unusable on small screens.
- Add a route-backed group filter that composes with every existing Devices filter, search term, and sort option.
- Preserve device-scoped authorization in group visibility, counts, filters, and membership mutations.
- Emit traceable group and membership audit events with actor, timestamp, affected device IDs, group ID, and action.

## Non-Goals

- Rule-based or automatically maintained groups.
- Nested groups or group hierarchy.
- Per-group RBAC or permission inheritance.
- Bulk device import or export.
- Replacing product, account, IPv4, approval, connectivity, search, or sort controls.
- Exposing a new public JSON:API or Go-client contract in this increment.

## User-Facing Behavior

The Devices view provides a focused group-management panel or modal. An unscoped device manager can create groups and
edit group metadata. Group names are case-insensitively unique across active and archived groups. Archival is the normal
removal action; archived groups leave normal lists and filters but retain identity and memberships for audit
interpretation. Actual audit-event retention remains deployment-log dependent. An archived empty group may be permanently
deleted through an explicit destructive confirmation. Archived groups can be restored with their reserved name.

Managers can select visible devices and add them to, or remove them from, a visible group. Bulk membership updates are
idempotent and all-or-nothing after authorization and current-state validation. Adding an existing membership and
removing an absent membership succeed as no-ops. Missing devices, a deleted or archived group, or changed authorization
produce a clear stale or unauthorized error without partially changing membership.

A view-only or scoped user sees a group only when it contains at least one device that user may view. Membership counts
and membership summaries include only viewable devices. Scoped device managers may add or remove only authorized devices
from visible groups, but only unscoped managers may create, rename, describe, archive, restore, or permanently delete
groups. Empty groups are therefore visible only to unscoped managers.

Active group filters use a stable group UUID in the `group_id` query parameter and display the current group name in the
active-filter chip. Invalid, archived, deleted, or unauthorized IDs are removed from the effective filter and produce a
non-disclosing empty or unavailable state. The parameter composes with all existing route-backed filter, search, and sort
state.

Desktop rows show a compact membership summary with a focused editing affordance. Small screens omit or collapse the
summary rather than forcing an unreadable table; detailed membership remains available from the group-management flow.
Loading, empty, unauthorized, archived, name-conflict, stale-target, and permanent-delete conflict states have explicit
feedback.

## Requirements

### Functional Requirements

- Add `DeviceGroup` and `DeviceGroupMembership` Ash resources inside the existing Devices domain boundary.
- Store group name, normalized name key, optional description, archive timestamp, and timestamps.
- Enforce nonblank names and case-insensitive uniqueness across active and archived records.
- Enforce one membership per device/group pair and allow each device to belong to multiple groups.
- Preserve memberships on archive and restore; reject permanent deletion unless the group is archived and empty.
- Remove memberships when a device is deleted without changing any other device lifecycle behavior.
- Provide context APIs for group CRUD, archive/restore/delete, scoped listing and counts, membership lookup, bulk
  assignment/removal, and device listing/filtering by group.
- Apply device authorization before group results or membership counts leave the server boundary.
- Pass a trusted server-built authorization value to every context mutation. It contains actor identity, management
  capability, whether management is unscoped, and the authorized device-ID scope; no value comes from LiveView event
  parameters.
- Restrict metadata lifecycle actions to unscoped device managers and membership actions to managers authorized for
  every submitted device, with transactional scope validation inside `Nixstasis.Devices`.
- Emit structured Logger and dedicated `device_group_audit` PubSub events following existing audit patterns. Every event
  includes the operator subject or a local-development actor marker, event timestamp, action, group ID, and affected
  device IDs.
- Add group membership loading and `group_id` filtering to `Devices.list_devices/1` without changing existing defaults.
- Extend Devices LiveView URL normalization, active-filter chips, clear-filter behavior, and preserved navigation state.
- Broadcast a payload-free `:device_groups_changed` invalidation on the existing `devices` topic after successful
  changes; connected LiveViews must perform authorization-scoped re-queries and never consume audit payloads for refresh.

### Quality Requirements

- Write behavior-focused tests before each implementation slice.
- Keep database uniqueness and foreign-key constraints authoritative under concurrent writes.
- Avoid N+1 membership queries when rendering visible device rows or group counts.
- Use existing LiveView streams and stable DOM IDs for collection rendering and tests.
- Ensure mutation errors are actionable to authorized users and non-disclosing to unauthorized users.
- Preserve responsive access to existing Devices actions and filters.

### Compatibility and Migration Requirements

- Create a named Ash migration and resource snapshots with `mix ash.codegen dashboard_device_groups`.
- Existing devices begin with no memberships; no data backfill is required.
- Existing Devices URLs and filters retain their behavior when `group_id` is absent.
- No device runtime, edge, client, JSON:API, command, approval, or remote-access payload changes are permitted.

## Existing Context

`Nixstasis.Devices.Device` is an Ash/PostgreSQL resource owned by `Nixstasis.Domain`. `Nixstasis.Devices.list_devices/1`
currently composes approval, connectivity, product, account, IPv4, search, and sort operations. Device authorization is
applied in `NixstasisWeb.DeviceLive.Index` through `NixstasisWeb.Permissions`, including explicit scoped device IDs.
The LiveView stores filter state in the route, streams devices, and already supports selection and bulk actions.

The delivered Device Detail Page established route-backed navigation and responsive degraded states. Dashboard Home
established context-owned device state and PubSub refreshes rather than duplicated UI state. Script and command-policy
features use structured Logger and PubSub audit emitters; device groups reuse that pattern instead of adding an audit
framework.

## Proposed Design

### Data and domain ownership

`Nixstasis.Devices.DeviceGroup` owns global group metadata. A normalized `name_key` is derived from the trimmed,
case-folded name and protected by a unique database index that includes archived rows. `archived_at` distinguishes active
and archived groups. `Nixstasis.Devices.DeviceGroupMembership` is an explicit join resource with unique `group_id` and
`device_id` identity and database foreign keys. Device deletion cascades membership removal; group deletion remains
restricted by both context validation and a membership-restricting foreign key.

`Nixstasis.Domain` exposes resource actions while `Nixstasis.Devices` remains the application context for group
lifecycle, scoped reads, bulk membership operations, and device filtering. No JSON:API route is added. Bulk mutations run
transactionally and validate the complete device set before writing.

### Authorization and scoped reads

The LiveView derives a trusted authorization value from `session["operator_context"]` and the existing device permission
map. The value carries `actor_id`, `can_manage_devices?`, `can_manage_all_devices?`, and `authorized_device_ids`.
`actor_id` is a required nonblank string: the trusted operator subject, with email as a server-side fallback and
`local-development` only when the existing local browser fallback is active. If subject and email are both absent on a
production claim path, authorization construction fails closed and no group mutation runs. Event parameters never supply
actor or permission data.

Unscoped metadata management requires `can_manage_all_devices?`. Membership mutation requires `can_manage_devices?` and
context-owned validation that every submitted device is present in `authorized_device_ids`; `nil` means unscoped, while
an empty set authorizes no devices. `Nixstasis.Devices` accepts the trusted value on every mutation and rejects the whole
transaction before writing when capability, scope, group state, or device state is invalid.

A scoped group listing joins through authorized memberships, returns distinct groups, and computes counts only over the
same authorized device scope. Filtering devices by group intersects group membership with every existing filter before
results are returned. Authorization is applied before rendering and re-applied on every mutation to reject stale client
selection.

### Lifecycle, audit, and refresh behavior

Archive sets `archived_at` and preserves identity and memberships. Restore clears it. Permanent delete requires archived
state and zero memberships and uses an explicit confirmation event. Existing case-insensitive uniqueness across archived
rows makes archive and restore deterministic and prevents name reuse from obscuring audit interpretation.

`Nixstasis.Devices.GroupAudit` generates the UTC timestamp after a successful transaction and emits create, update,
archive, restore, permanent-delete, membership-add, and membership-remove events through Logger and the dedicated
`device_group_audit` PubSub topic. Audit payloads contain the trusted actor ID, timestamp, group ID, affected device IDs,
and action. They are not used for UI refresh.

After successful lifecycle or membership changes, `Nixstasis.Devices` separately broadcasts the payload-free atom
`:device_groups_changed` on the existing `devices` topic. Connected LiveViews respond only by re-running scoped group and
device queries, so no group, actor, or device identity leaks through the invalidation message.

### LiveView interaction

The existing `/devices` LiveView remains the only route. A focused modal or panel owns group forms and active/archived
management. Existing selected-device actions gain add-to-group and remove-from-group controls. Metadata controls are
hidden from scoped and view-only users; event handlers enforce the same checks server-side.

The `group_id` URL parameter is incorporated into `get_params/1`, active filters, clear filters, and every generated
filter link. Visible devices are loaded with scoped group memberships in one query or bounded preload. Desktop presents
compact group chips or a count-plus-summary; small screens defer detail to the focused group flow.

## Architecture Consistency

### Existing Patterns Reused

- Ash resources and named Ash code generation for persisted server domain state.
- `Nixstasis.Devices` as the context boundary and `Nixstasis.Domain` for resource actions.
- Route-backed Devices filters and LiveView streams.
- `NixstasisWeb.Permissions` device scopes and fail-closed event-handler checks.
- Logger and PubSub audit events used by scripts and command policies.
- Device PubSub refresh behavior for connected views.

### Invariants Preserved

- Groups never change device identity, registration, approval, heartbeat, API tokens, commands, or remote access.
- Caddy/AuthCrunch remains the browser authentication edge; Phoenix remains the application authorization backstop.
- Scoped users cannot infer inaccessible device IDs or counts through group metadata.
- Existing Devices URLs, filters, search, sort, and navigation continue to work unchanged without `group_id`.
- The Go client and device runtime contracts remain unchanged.

### New Decisions Introduced

- Group names are case-insensitively unique across active and archived records.
- Archive is the default removal path; only empty archived groups can be permanently deleted.
- Scoped users see only groups with authorized memberships and only scoped membership counts.
- Only unscoped device managers control global group metadata; scoped managers can mutate authorized memberships.
- Bulk membership writes are transactional and all-or-nothing.

### Architecture Documentation Changes

Update `docs/src/architecture.md` to add manual device groups to the product data model and describe scoped group
membership as server-owned organization that does not affect runtime identity or behavior.

## Operational Considerations

No new service, process, environment variable, or external dependency is introduced. PostgreSQL stores group state and
constraints. Operators recover an accidental archive by restoring the group. Permanent deletion is intentionally narrow
and unavailable until every membership has been removed. Structured audit events use the deployment's existing log
retention; PubSub supports current UI consumers but is not a durable event store.

Support diagnostics should distinguish uniqueness conflict, archived target, nonempty permanent-delete conflict,
unauthorized device set, and stale target. Feature-specific telemetry is deferred; the first increment relies on
structured audit logs and existing application observability.

## Documentation Impact

| Documentation concern      | Exact page                                           | Create or update | Planned change                                                        | Owning Beads task               |
|----------------------------|------------------------------------------------------|------------------|-----------------------------------------------------------------------|---------------------------------|
| Introduction               | `docs/src/README.md`                                 | Update           | Mention manual fleet organization in the operator capability summary  | `nixstasis-vpu.7.8`             |
| Architecture               | `docs/src/architecture.md`                           | Update           | Record group ownership, scope, and preserved device invariants        | `nixstasis-vpu.7.8`             |
| Usage / Operations         | `docs/src/operations/device-groups.md`               | Create           | Explain lifecycle, memberships, filters, scoped counts, and conflicts | `nixstasis-vpu.7.8`             |
| Module reference           | `docs/src/modules/server-devices.md`                 | Update           | Document resource, context, permission, and audit interfaces          | `nixstasis-vpu.7.8`             |
| Development                | Not applicable                                       | —                | Existing server development guidance remains sufficient               | —                               |
| Reference                  | Not applicable                                       | —                | No public API or configuration contract is added                      | —                               |
| Navigation                 | `docs/src/SUMMARY.md`                                | Update           | Register design now; add operations page and delivered record later   | `nixstasis-vpu.1`, `.7.8`, `.8` |
| Implemented Feature Record | `docs/src/features/dashboard-device-groups/index.md` | Create close-out | Preserve delivery and audit history and add to Implemented Features   | `nixstasis-vpu.8`               |

## Validation Strategy

- `mix test test/nixstasis/device_groups_test.exs`
- `mix test test/nixstasis/devices_test.exs`
- `mix test test/nixstasis_web/permissions_test.exs`
- `mix test test/nixstasis_web/live/device_live_test.exs`
- `mix ash.codegen --check`
- `mix format --check-formatted`
- `mix credo --strict`
- `mix precommit`
- `uv run scripts/check-docs.py`
- `mdbook build docs`
- `mise run check` after the repository-wide Markdown validation issue `nixstasis-63w` is resolved; until then, record
  that known limitation and run changed-file hooks plus all feature-specific checks.
- For every implementation child, run its focused checks while editing. Once fixes stabilize, invoke the repository-wide
  suite once immediately before that child's commit. Until `nixstasis-63w` closes, record its known Rumdl failure and use
  successful changed-file hooks plus affected package tests as the commit gate; reuse successful package evidence only
  when no relevant package file changed.
- Manual responsive checks for group management, group chips or summaries, filter preservation, empty states, conflict
  feedback, and keyboard operation.
- Permission checks using unscoped manager, scoped manager, scoped viewer, empty scope, and denied sessions.

## Implementation Decomposition

- `nixstasis-vpu.7.1` (DGD-001) owns resource/database lifecycle actions, invariants, relationships, named migration,
  and focused resource tests. Validation: focused tests, codegen check, formatter, and Credo. Commit: persistence only.
- `nixstasis-vpu.7.2` (DGD-002) owns scoped query/filter APIs, trusted authorization construction, and authorized
  `Nixstasis.Devices` orchestration for metadata create, update, archive, restore, and permanent delete. Validation:
  focused group, Devices, and Permissions tests, formatter, and Credo. Commit: reads, authorization, and metadata context
  orchestration only.
- `nixstasis-vpu.7.3` (DGD-003) owns transactional, idempotent membership mutation orchestration and failure semantics.
  Validation: focused group and Devices tests, formatter, and Credo. Commit: membership mutations only.
- `nixstasis-vpu.7.4` (DGD-004) owns post-transaction audit emission and payload-free UI invalidation. Validation:
  focused audit, context, and refresh tests, formatter, and Credo. Commit: audit and refresh integration only.
- `nixstasis-vpu.7.5` (DGD-005) owns behavior-first LiveView tests and group metadata lifecycle UI states. Validation:
  focused DeviceLive tests, formatter, Credo, and keyboard checks. Commit: metadata management UI only.
- `nixstasis-vpu.7.6` (DGD-006) owns behavior-first LiveView tests and selected-device membership workflows. Validation:
  focused DeviceLive tests, formatter, Credo, and permission-state checks. Commit: membership UI only.
- `nixstasis-vpu.7.7` (DGD-007) owns behavior-first route/filter tests and responsive membership summaries. Validation:
  focused DeviceLive and Devices tests, formatter, Credo, and browser checks. Commit: route and presentation only.
- `nixstasis-vpu.7.8` (DGD-008) owns `docs/src/README.md`, `docs/src/architecture.md`, the new
  `docs/src/operations/device-groups.md`, `docs/src/modules/server-devices.md`, and operations navigation. Validation:
  strict docs checks, mdBook build, and changed-file Markdown checks. Commit: reader-facing documentation only.

## Dependencies and Parallelism

The implementation chain is DGD-001 through DGD-008 in order. Persistence precedes scoped reads; scoped reads precede
membership writes; mutation contracts precede audit and refresh integration; metadata UI precedes membership UI; route
filtering and responsive summaries follow both UI workflows; documentation follows stable behavior. Serial execution
avoids conflicts in the shared context and Devices LiveView. Every task also depends on lifecycle `spec-reconcile`.

## Rollout and Migration

The named Ash migration creates empty group and membership tables and indexes. Deployment requires the normal server
migration step; no backfill or compatibility window is needed. The feature becomes available when the migrated server is
started. Before operators create group data, rollback may remove the new empty tables. After use, destructive rollback is
unsupported without an explicit backup/export of group and membership data; prefer a forward-fix migration.

## Risks and Tradeoffs

- Many-to-many joins can multiply rows; distinct queries and indexes must keep filters and counts correct.
- Scoped counts can differ between operators by design and must be labeled as visible-device counts where ambiguity
  exists.
- Logger-based audit history follows the established project pattern but depends on deployment log retention.
- Keeping archived names reserved reduces accidental history ambiguity but requires permanent deletion before reuse.
- Extending the dense Devices view risks clutter; a compact summary and focused editor keep the primary table usable.

## Rejected Alternatives

- Automatic, nested, and RBAC-bearing groups exceed the manual organization outcome.
- Hard deletion as the normal removal path would erase useful lifecycle context and complicate membership safety.
- Reusing names after archive would make restoration and audit interpretation ambiguous.
- Showing all global group metadata to scoped users would leak organization and inaccessible membership information.
- A separate group service, public API, or audit subsystem would add boundaries not required by the feature.
- Client-side authorization or filtering after loading global memberships would violate the server authorization boundary.

## Open Questions

None blocking implementation.

## Deferred Decisions

Dynamic groups, nested groups, per-group RBAC, public API exposure, and durable database-backed audit history remain out
of scope. Revisit them only through a separately designed feature.

## Planning Record

### Questions Asked and Answers

- Removal lifecycle: archive by default, with explicit permanent deletion for empty archived groups.
- Scoped visibility: show a group only when it has at least one viewable device; counts include only viewable devices.
- Name uniqueness: case-insensitive uniqueness across active and archived groups.
- Scoped metadata management: only unscoped device managers control group metadata; scoped managers may mutate
  authorized memberships.

### Assumptions

- Existing `operator_context` subject identifies the actor; local development uses an explicit local actor marker.
- The existing Logger and PubSub audit pattern satisfies the first increment's traceability requirement.
- Group metadata is global server state rather than account-scoped state because no account tenancy boundary exists.

### Design Changes During Planning

The migrated roadmap's ambiguous archive/delete wording was resolved into a reversible archive lifecycle and a narrow
permanent-delete rule. Scoped visibility, count semantics, global name uniqueness, and scoped-manager capabilities were
made explicit before task creation.

Independent architecture, simplicity, documentation, and execution reviews then clarified context-owned authorization,
trusted actor propagation, separate audit and refresh events, rollback safety, idempotent membership semantics,
standalone operator documentation, and eight bounded implementation slices. Replacement reviews approved every
reconciled domain with no remaining findings.

### Source Material

- `docs/src/planned-features.md`, Dashboard device groups section
- `docs/src/architecture.md`
- `docs/src/modules/server-devices.md`
- `docs/src/features/device-detail-page/index.md`
- `docs/src/features/dashboard-home/index.md`
- `packages/server/lib/nixstasis/devices.ex`
- `packages/server/lib/nixstasis/devices/device.ex`
- `packages/server/lib/nixstasis/domain.ex`
- `packages/server/lib/nixstasis_web/live/device_live/index.ex`
- `packages/server/lib/nixstasis_web/live/device_live/index.html.heex`
- `packages/server/lib/nixstasis_web/operator_context.ex`
- `packages/server/lib/nixstasis_web/permissions.ex`
- Existing server device, permission, and LiveView tests
