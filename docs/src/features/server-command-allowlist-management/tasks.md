# Tasks: Server Command Allowlist Management

- **[P]**: Can run in parallel after dependencies for the phase are complete.
- **[Story]**: User story owning the task.
- Include exact file paths in implementation task descriptions.

## Phase 0: Scope Guard And Authorization

- [X] T000 Confirm this feature remains distinct from script workbench execution and dashboard device groups. Scope the feature to allowlist policy lifecycle only.
- [X] T001 Require operator-level permission for creating/updating/deleting command entries, categories, and assignments; restrict viewers to policy status only.
- [X] T002 Confirm device-level authorization/visibility rules are applied in all screens and assignment APIs, with assignments limited to approved devices.

## Phase 1: Policy Domain And Persistence

- [X] T003 Add persistence and Ash resources for command entries, immutable versions, archive state, and case-insensitive names under `packages/server/lib/nixstasis/command_allowlists/`.
- [X] T004 Add persistence and resources for first-class category tags with slug/display name/description under `packages/server/lib/nixstasis/command_allowlists/`, plus command-entry category associations.
- [X] T005 Add persistence and resources for per-device policy assignments, version-pinned sources, resolved effective policy snapshots, monotonic per-device revisions, and optional drift warning state under `packages/server/lib/nixstasis/command_allowlists/`.
- [X] T006 Add persistence and resources for policy delivery/client response history under `packages/server/lib/nixstasis/command_allowlists/`.
- [X] T007 Add database/resource constraints to validate absolute paths and prevent conflicting command name entries within the same resolved policy.
- [X] T008 Add repository migrations with `mix ash.codegen <descriptive_name>` and verify with `mix ash.codegen --check` if resource shape changes.

## Phase 2: Validation And Resolution

- [X] T009 Implement input validation for command entries: strict lowercase name format, absolute path syntax, no whitespace/shell metacharacters, no server-side existence check, and web validation layer for create/edit forms.
- [X] T010 Implement conflict detection and effective policy resolution for selected command entries and category tags in `packages/server/lib/nixstasis/domain.ex` and allowlist resolution service; same name/same path deduplicates with provenance, same name/different path blocks the affected target assignment.
- [X] T011 Add server-side preview generation and mandatory confirmation for effective policy before assignment in `packages/server/lib/nixstasis/domain.ex` and command-preview UX endpoint, including combined policy, provenance, diff, conflicts, affected devices, and raw payload preview.
- [ ] T012 Add audit events for create/update/delete, assignment state changes, and revoke/narrow deliveries in policy resources and `packages/server/lib/nixstasis_web/live/`.

## Phase 3: Policy Delivery Integration

- [X] T013 Add server command delivery path using `packages/server/lib/nixstasis/devices.ex`, `packages/server/lib/nixstasis/devices/pending_command.ex`, versioned content type, inline-first/deferred-ref payload serialization, and superseding of older undelivered policy commands for a device.
- [X] T014 Implement idempotent client command application using `packages/client/internal/commands/handler.go`, command IDs, device command acknowledgements, and same-revision conflict rejection.
- [X] T015 Add client persistence for received policy outside the script directory, reload into `packages/client/internal/script.RuntimeConfig` from `packages/client/cmd/nixstasis/poll.go`, and server-policy-overrides-local-config behavior.
- [X] T016 Record client delivery outcomes from `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex` and tie them to assignment state in persistence, including durable ack, unsupported, stale, conflict, and persistence failure reasons.
- [X] T017 Handle unsupported/legacy clients with explicit command-result failure/reporting path and operator-visible assignment status.

## Phase 4: LiveView Workbench

- [X] T018 Add Scripts → Command Policies LiveView entry inventory under `packages/server/lib/nixstasis_web/live/` with modal create/edit, category tags, filters, copy path, assignment counts, disable/duplicate, and assign shortcut.
- [ ] T019 Add category tag management UI with modal create/edit, command-entry count, active device-assignment count, delete blocking only when active assignments select the category, and assign shortcut.
- [ ] T020 Add approved-device assignment wizard with scoped device selection, entry/category selection, preview/confirm, batch handling that excludes conflicted devices, and simple revoke-all confirmation.
- [ ] T021 Add assignment result/status display and retry/resend, remove selected sources, revoke all, rollback-as-new-revision, raw payload debug for operators/admins, pending-offline state, unsupported-client guidance, activity events, and optional drift warning controls.
- [ ] T022 Add periodic/manual refresh for policy and assignment statuses where useful; real-time PubSub is out of scope for v1.

## Phase 5: Verification And Close-Out

- [ ] T023 Add server tests for policy persistence, category tags, delete/disable rules, version pinning, conflict detection, assignment authorization, approved-device-only assignment, command queueing, result acknowledgement, superseding, revoke/narrow behavior, rollback, optional drift warning, and audit events.
- [ ] T024 Add client tests for policy ingestion, persistence/reload, server-policy-overrides-local behavior, revision ordering, idempotency, and `exec_cmd` gating with policy presence/absence.
- [ ] T025 Add integration test covering add policy, assign to one+ devices, resolve, verify command behavior, revoke assignment, and verify rejection on the next poll cycle.
- [ ] T026 Run `hk check -a` and required focused test suites after implementation changes.
- [ ] T027 Update user-facing docs in affected sections listed in `design.md` and run doc build checks.
- [ ] T999 Complete close-out by reconciling implementation, feature specs, and planned docs status.
