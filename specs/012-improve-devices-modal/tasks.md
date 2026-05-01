# Tasks: Devices Page and Device Modal Improvements

**Input**: Design documents from `/specs/012-improve-devices-modal/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are MANDATORY for APIs and complex logic (per Constitution). Include test tasks unless explicitly exempted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare baseline docs and fixtures for implementation and validation.

 - [X] T001 Align feature documentation cross-links in specs/012-improve-devices-modal/spec.md and specs/012-improve-devices-modal/quickstart.md
 - [X] T002 [P] Add reusable Devices LiveView test fixture helpers for product/account/status combinations in packages/server/test/support/live_view_test_helpers.ex

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core filter state and query plumbing required by all user stories.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

 - [X] T003 Implement additive filter-state merge and clear helpers in packages/server/lib/nixstasis_web/live/device_live/index.ex
 - [X] T004 [P] Extend device list query API to accept product/account_number/status filter map in packages/server/lib/nixstasis/devices.ex
 - [X] T005 [P] Add filter validation and nil-safe matching logic in packages/server/lib/nixstasis/devices/device.ex
 - [X] T006 Wire foundational filter params through Devices LiveView mount/handle_params in packages/server/lib/nixstasis_web/live/device_live/index.ex
 - [X] T007 Add foundational unit/integration coverage for filter-state transitions and query filtering in packages/server/test/nixstasis/devices_test.exs

**Nixstasis**: Foundation ready - user story implementation can now begin.

---

## Phase 3: User Story 1 - Browse devices efficiently (Priority: P1) 🎯 MVP

**Goal**: Improve list readability and enable clickable additive filtering for Product, Account Number, and Status.

**Independent Test**: Open Devices page, verify `MAC Address` + `Product` columns, click Product/Status/Account values to add AND filters, remove one chip, then clear all filters.

### Tests for User Story 1

 - [X] T008 [P] [US1] Add LiveView test coverage for column labels and Product column rendering in packages/server/test/nixstasis_web/live/device_live_test.exs
 - [X] T009 [P] [US1] Add LiveView test coverage for additive click-to-filter behavior in packages/server/test/nixstasis_web/live/device_live_test.exs
 - [X] T010 [P] [US1] Add LiveView test coverage for per-filter chip removal and clear-all behavior in packages/server/test/nixstasis_web/live/device_live_test.exs
 - [X] T030 [P] [US1] Add BDD-style contract test for GET /api/v1/devices filtering in packages/server/test/nixstasis_web/controllers/device_controller_test.exs
 - [X] T031 [P] [US1] Add responsive behavior coverage for mobile and desktop filter interactions in packages/server/test/nixstasis_web/live/device_live_test.exs

### Implementation for User Story 1

 - [X] T011 [US1] Rename `Device Name` header to `MAC Address` and add `Product` column markup in packages/server/lib/nixstasis_web/live/device_live/index.html.heex
 - [X] T012 [US1] Implement clickable Product/Account Number/Status cell events in packages/server/lib/nixstasis_web/live/device_live/index.html.heex
 - [X] T013 [US1] Implement filter chip UI with per-chip remove actions and `Clear all` control in packages/server/lib/nixstasis_web/live/device_live/index.html.heex
 - [X] T014 [US1] Implement filter click/clear event handlers and assigns updates in packages/server/lib/nixstasis_web/live/device_live/index.ex
 - [X] T015 [US1] Ensure list refresh preserves deterministic ordering and empty-state messaging under active filters in packages/server/lib/nixstasis_web/live/device_live/index.ex

**Nixstasis**: User Story 1 is independently functional and testable.

---

## Phase 4: User Story 2 - Open device details modal from devices page (Priority: P1)

**Goal**: Make MAC Address the canonical modal entrypoint and preserve list context after close.

**Independent Test**: Click MAC Address, confirm device modal opens for selected device, close modal, and verify existing filters/scroll context persist.

### Tests for User Story 2

 - [X] T016 [P] [US2] Add LiveView test for MAC Address link opening selected device modal in packages/server/test/nixstasis_web/live/device_live_test.exs
 - [X] T017 [P] [US2] Add LiveView test for modal close returning to prior filter context in packages/server/test/nixstasis_web/live/device_live_test.exs
 - [X] T032 [P] [US2] Add BDD-style contract test for POST /api/v1/devices/{device_id}/modal in packages/server/test/nixstasis_web/controllers/device_controller_test.exs
 - [X] T033 [P] [US2] Add BDD-style contract test for DELETE /api/v1/devices/{device_id}/modal in packages/server/test/nixstasis_web/controllers/device_controller_test.exs
 - [X] T034 [US2] Add modal-open latency verification for SC-002 (p95 <= 2s) in packages/server/test/nixstasis_web/live/device_live_test.exs

### Implementation for User Story 2

 - [X] T018 [US2] Render MAC Address cell as modal-opening link with selected device binding in packages/server/lib/nixstasis_web/live/device_live/index.html.heex
 - [X] T019 [US2] Wire MAC-link modal open events to existing device show flow in packages/server/lib/nixstasis_web/live/device_live/index.ex
 - [X] T020 [US2] Preserve filter/query and scroll context on modal open/close route transitions in packages/server/lib/nixstasis_web/live/device_live/index.ex
 - [X] T035 [US2] Implement GET /api/v1/devices filter parameter handling contract in packages/server/lib/nixstasis_web/controllers/device_controller.ex
 - [X] T036 [US2] Implement POST and DELETE /api/v1/devices/{device_id}/modal contract endpoints in packages/server/lib/nixstasis_web/controllers/device_controller.ex

**Nixstasis**: User Stories 1 and 2 work independently, with modal access integrated from Devices page.

---

## Phase 5: User Story 3 - Handle unavailable or stale device data gracefully (Priority: P2)

**Goal**: Ensure robust user feedback for modal/data unavailability and list/modal state consistency.

**Independent Test**: Simulate unavailable device details and connection disruptions; verify clear messages, retry paths, and no contradictory stale data between list and modal.

### Tests for User Story 3

 - [X] T021 [P] [US3] Add LiveView test coverage for modal error and retry messaging when details fail to load in packages/server/test/nixstasis_web/live/device_live_test.exs
 - [X] T022 [P] [US3] Add channel-level resilience test for terminal interruption/recovery expectations in packages/server/test/nixstasis_web/channels/terminal_channel_test.exs
 - [X] T023 [P] [US3] Add domain test coverage for unauthorized or missing-device modal access in packages/server/test/nixstasis/devices_test.exs

### Implementation for User Story 3

 - [X] T024 [US3] Harden modal open path for missing/unauthorized devices with user-visible feedback in packages/server/lib/nixstasis_web/live/device_live/show.ex
 - [X] T025 [US3] Ensure modal PCP and terminal tabs show degraded/retry states without crashing view in packages/server/lib/nixstasis_web/live/device_live/show.html.heex
 - [X] T026 [US3] Align remote access session cleanup and stale-state refresh on modal close/reopen in packages/server/lib/nixstasis_web/live/device_live/show.ex
 - [X] T037 [US3] Add telemetry events for device-discovery and modal-open failure paths in packages/server/lib/nixstasis_web/live/device_live/index.ex
 - [X] T038 [US3] Add support-ticket reduction measurement procedure for SC-004 in specs/012-improve-devices-modal/quickstart.md

**Nixstasis**: All user stories are functional and independently testable.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and cleanup across all stories.

 - [X] T027 [P] Run and stabilize targeted test suites for devices LiveView and terminal channel in packages/server/test/nixstasis_web/live/device_live_test.exs and packages/server/test/nixstasis_web/channels/terminal_channel_test.exs
 - [X] T028 [P] Update feature verification notes with final behavior checks in specs/012-improve-devices-modal/quickstart.md
 - [X] T029 Execute full quickstart validation flow and capture completion notes in specs/012-improve-devices-modal/tasks.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies.
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks all user story work.
- **Phase 3 (US1)**: Depends on Phase 2.
- **Phase 4 (US2)**: Depends on Phase 2 and integrates with US1 list UI changes.
- **Phase 5 (US3)**: Depends on Phase 2 and reuses US2 modal entrypoint.
- **Phase 6 (Polish)**: Depends on completion of selected user stories.

### User Story Dependencies

- **US1 (P1)**: No dependency on other stories after foundational work.
- **US2 (P1)**: Depends on US1 table rendering changes for MAC link location.
- **US3 (P2)**: Depends on US2 modal launch path and existing spec-005 modal capabilities.

### Within Each User Story

- Tests added first and expected to fail before implementation.
- LiveView template event wiring before full state-handler logic where applicable.
- UI and behavior changes complete before final story verification checkpoint.

### Parallel Opportunities

- Foundational tasks T004 and T005 can run in parallel.
- US1 tests T008-T010, T030, and T031 can run in parallel.
- US2 tests T016-T017 and T032-T033 can run in parallel.
- US3 tests T021-T023 can run in parallel.
- Polish tasks T027 and T028 can run in parallel.

---

## Parallel Example: User Story 1

```bash
Task: "Add LiveView test coverage for column labels and Product column rendering in packages/server/test/nixstasis_web/live/device_live_test.exs"
Task: "Add LiveView test coverage for additive click-to-filter behavior in packages/server/test/nixstasis_web/live/device_live_test.exs"
Task: "Add LiveView test coverage for per-filter chip removal and clear-all behavior in packages/server/test/nixstasis_web/live/device_live_test.exs"
```

## Parallel Example: User Story 2

```bash
Task: "Add LiveView test for MAC Address link opening selected device modal in packages/server/test/nixstasis_web/live/device_live_test.exs"
Task: "Add LiveView test for modal close returning to prior filter context in packages/server/test/nixstasis_web/live/device_live_test.exs"
```

## Parallel Example: User Story 3

```bash
Task: "Add LiveView test coverage for modal error and retry messaging when details fail to load in packages/server/test/nixstasis_web/live/device_live_test.exs"
Task: "Add channel-level resilience test for terminal interruption/recovery expectations in packages/server/test/nixstasis_web/channels/terminal_channel_test.exs"
Task: "Add domain test coverage for unauthorized or missing-device modal access in packages/server/test/nixstasis/devices_test.exs"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 and Phase 2.
2. Deliver Phase 3 (US1) for table usability, additive filtering, and filter removal behavior.
3. Validate US1 independently using defined test criteria and quickstart subset.

### Incremental Delivery

1. Add US1 (improved list + filters) and validate.
2. Add US2 (MAC link modal integration) and validate.
3. Add US3 (resilience/error-state hardening) and validate.
4. Finish with Phase 6 polish and full quickstart execution.

### Parallel Team Strategy

1. One developer handles foundational query/filter plumbing (Phase 2).
2. Second developer prepares US1 test coverage and template updates once Phase 2 lands.
3. Third developer can prepare US3 channel/domain tests in parallel after Phase 2 while US2 modal link wiring proceeds.
