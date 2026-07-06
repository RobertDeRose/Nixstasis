# Tasks: Server Command Allowlist Management

- **[P]**: Can run in parallel after dependencies for the phase are complete.
- **[Story]**: User story owning the task.
- Include exact file paths in implementation task descriptions.

## Phase 0: Scope Guard And Authorization

- [ ] T000 Confirm this feature remains distinct from script workbench execution and dashboard device groups. Scope the feature to allowlist policy lifecycle only.
- [ ] T001 Require operator-level permission for creating/updating/deleting allowlists, categories, and assignments.
- [ ] T002 Confirm device-level authorization/visibility rules are applied in all screens and assignment APIs.

## Phase 1: Policy Domain And Persistence

- [ ] T003 Add persistence and Ash resources for command allowlist entries and versions.
- [ ] T004 Add persistence and resources for allowlist categories and membership.
- [ ] T005 Add persistence and resources for device policy assignments and effective policy snapshots.
- [ ] T006 Add persistence and resources for policy delivery/client response history.
- [ ] T007 Add database constraints to validate absolute paths and prevent conflicting command name entries within the same resolved policy.
- [ ] T008 Add repository migrations and `ash.codegen` validation if resource shape changes.

## Phase 2: Validation And Resolution

- [ ] T009 Implement input validation for command entries: name/path format, shell fragments, shell metacharacters, and path normalization in `packages/server/lib/nixstasis/command_allowlist/` resources and web validation layer for create/edit forms.
- [ ] T010 Implement conflict detection and effective policy resolution for category composition in `packages/server/lib/nixstasis/domain.ex` and allowlist resolution service.
- [ ] T011 Add server-side preview generation for effective policy before assignment in `packages/server/lib/nixstasis/domain.ex` and command-preview UX endpoint.
- [ ] T012 Add audit events for create/update/delete and assignment state changes in policy resources and `packages/server/lib/nixstasis_web/live/`.

## Phase 3: Policy Delivery Integration

- [ ] T013 Add server command delivery path (likely `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex` + command payload serialization) to push policy updates to selected devices.
- [ ] T014 Implement idempotent delivery semantics using `packages/client/internal/commands/handler.go`, command IDs, and device command acknowledgements.
- [ ] T015 Add command payload schema version marker and client persistence for received policy in `packages/client/internal/script/runtime.go`.
- [ ] T016 Record client delivery outcomes and tie to assignment state in persistence and command result persistence.
- [ ] T017 Handle unsupported/legacy clients with explicit failure/reporting path and operator-visible status.

## Phase 4: LiveView Workbench

- [ ] T018 Add command allowlist inventory and CRUD UI screens under `packages/server/lib/nixstasis_web/live/`.
- [ ] T019 Add category management screen with conflict-aware effective policy preview.
- [ ] T020 Add device assignment screen with visibility by authorization scope.
- [ ] T021 Add assignment result/status display and retry/resend controls.
- [ ] T022 Add live refresh for policy and assignment statuses where useful.

## Phase 5: Verification And Close-Out

- [ ] T023 Add server tests for policy persistence, conflict detection, assignment authorization, and audit events.
- [ ] T024 Add client tests for policy ingestion and `exec_cmd` gating with policy presence/absence.
- [ ] T025 Add integration test covering add policy, assign to one+ devices, resolve, and verify command behavior.
- [ ] T026 Run `hk check -a` and required focused test suites after implementation changes.
- [ ] T027 Update user-facing docs in affected sections and run doc build checks.
- [ ] T999 Complete close-out by reconciling implementation, feature specs, and planned docs status.
