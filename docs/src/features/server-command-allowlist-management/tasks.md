# Tasks: Server Command Allowlist Management

- **[P]**: Can run in parallel after dependencies for the phase are complete.
- **[Story]**: User story owning the task.
- Include exact file paths in implementation task descriptions.

## Phase 0: Scope Guard And Authorization

- [X] T000 Confirm this feature remains distinct from script workbench execution and dashboard device groups. Scope the feature to allowlist policy lifecycle only.
- [ ] T001 Require operator-level permission for creating/updating/deleting allowlists, categories, and assignments.
- [ ] T002 Confirm device-level authorization/visibility rules are applied in all screens and assignment APIs.

## Phase 1: Policy Domain And Persistence

- [ ] T003 Add persistence and Ash resources for command allowlist entries and versions under `packages/server/lib/nixstasis/command_allowlists/`.
- [ ] T004 Add persistence and resources for direct-only allowlist categories and membership under `packages/server/lib/nixstasis/command_allowlists/`.
- [ ] T005 Add persistence and resources for device policy assignments and effective policy snapshots under `packages/server/lib/nixstasis/command_allowlists/`.
- [ ] T006 Add persistence and resources for policy delivery/client response history under `packages/server/lib/nixstasis/command_allowlists/`.
- [ ] T007 Add database/resource constraints to validate absolute paths and prevent conflicting command name entries within the same resolved policy.
- [ ] T008 Add repository migrations with `mix ash.codegen <descriptive_name>` and verify with `mix ash.codegen --check` if resource shape changes.

## Phase 2: Validation And Resolution

- [ ] T009 Implement input validation for command entries: name/path format, shell fragments, shell metacharacters, and path normalization in `packages/server/lib/nixstasis/command_allowlists/` resources and web validation layer for create/edit forms.
- [ ] T010 Implement conflict detection and effective policy resolution for direct category composition in `packages/server/lib/nixstasis/domain.ex` and allowlist resolution service.
- [ ] T011 Add server-side preview generation for effective policy before assignment in `packages/server/lib/nixstasis/domain.ex` and command-preview UX endpoint.
- [ ] T012 Add audit events for create/update/delete, assignment state changes, and revoke/narrow deliveries in policy resources and `packages/server/lib/nixstasis_web/live/`.

## Phase 3: Policy Delivery Integration

- [ ] T013 Add server command delivery path using `packages/server/lib/nixstasis/devices.ex`, `packages/server/lib/nixstasis/devices/pending_command.ex`, and command payload serialization to push `apply_command_policy` updates to selected devices.
- [X] T014 Implement idempotent client command application using `packages/client/internal/commands/handler.go`, command IDs, and device command acknowledgements.
- [ ] T015 Add client persistence for received policy and reload into `packages/client/internal/script.RuntimeConfig` from `packages/client/cmd/nixstasis/poll.go`.
- [ ] T016 Record client delivery outcomes from `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex` and tie them to assignment state in persistence.
- [ ] T017 Handle unsupported/legacy clients with explicit command-result failure/reporting path and operator-visible assignment status.

## Phase 4: LiveView Workbench

- [ ] T018 Add command allowlist inventory and CRUD UI screens under `packages/server/lib/nixstasis_web/live/`.
- [ ] T019 Add category management screen with conflict-aware effective policy preview.
- [ ] T020 Add device assignment screen with visibility by authorization scope.
- [ ] T021 Add assignment result/status display and retry/resend controls.
- [ ] T022 Add live refresh for policy and assignment statuses where useful.

## Phase 5: Verification And Close-Out

- [ ] T023 Add server tests for policy persistence, conflict detection, assignment authorization, command queueing, result acknowledgement, revoke/narrow behavior, and audit events.
- [ ] T024 Add client tests for policy ingestion, persistence/reload, idempotency, and `exec_cmd` gating with policy presence/absence.
- [ ] T025 Add integration test covering add policy, assign to one+ devices, resolve, verify command behavior, revoke assignment, and verify rejection.
- [ ] T026 Run `hk check -a` and required focused test suites after implementation changes.
- [ ] T027 Update user-facing docs in affected sections listed in `design.md` and run doc build checks.
- [ ] T999 Complete close-out by reconciling implementation, feature specs, and planned docs status.
