# Tasks: Schema-Driven Builder Dropdowns

**Input**: Design documents from `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/009-build-schema-dropdowns/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/schema-builder-options.openapi.yaml, quickstart.md

**Tests**: Tests are MANDATORY for APIs and complex logic (per Constitution). Include test tasks unless explicitly exempted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish feature scaffolding and test harness targets.

- [x] T001 Create schema-dropdown feature module stubs in `packages/server/lib/nixstasis/schema_options.ex` and `packages/server/lib/nixstasis/schema_options/normalizer.ex`
- [x] T002 Create LiveView test files for alert/report builders in `packages/server/test/nixstasis_web/live/alerts_live_test.exs` and `packages/server/test/nixstasis_web/live/reports_live_test.exs`
- [x] T003 [P] Create controller/API test file stubs in `packages/server/test/nixstasis_web/controllers/builder_schema_controller_test.exs` and `packages/server/test/nixstasis_web/controllers/builder_config_validation_controller_test.exs`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core schema-option loading and validation infrastructure required by all user stories.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T004 Implement schema reference discovery and option loading service in `packages/server/lib/nixstasis/schema_options.ex`
- [x] T005 [P] Implement schema option normalization, ordering, and duplicate-label disambiguation in `packages/server/lib/nixstasis/schema_options/normalizer.ex`
- [x] T006 [P] Implement selection validation and invalid-slot detection logic in `packages/server/lib/nixstasis/schema_options/validator.ex`
- [x] T007 Add builder schema options API controller and JSON rendering in `packages/server/lib/nixstasis_web/controllers/builder_schema_controller.ex` and `packages/server/lib/nixstasis_web/controllers/builder_schema_json.ex`
- [x] T008 [P] Add builder configuration validation API controller and JSON rendering in `packages/server/lib/nixstasis_web/controllers/builder_config_validation_controller.ex` and `packages/server/lib/nixstasis_web/controllers/builder_config_validation_json.ex`
- [x] T009 Wire new API routes in `packages/server/lib/nixstasis_web/router.ex`
- [x] T010 [P] Add unit tests for normalizer and validator logic in `packages/server/test/nixstasis/schema_options/normalizer_test.exs` and `packages/server/test/nixstasis/schema_options/validator_test.exs`
- [x] T011 Add controller tests for schema listing/options/validation contracts in `packages/server/test/nixstasis_web/controllers/builder_schema_controller_test.exs` and `packages/server/test/nixstasis_web/controllers/builder_config_validation_controller_test.exs`

**Nixstasis**: Shared schema-option services and API contracts are test-covered and ready for builder integration.

---

## Phase 3: User Story 1 - Select Valid Fields from Schema (Priority: P1) 🎯 MVP

**Goal**: Replace free-text field/path entry with schema-driven dropdown selection in alert and report builders.

**Independent Test**: Open alerts and reports builders, select a schema, and verify dropdown options are schema-derived, selectable, and persist correctly in saved payloads.

### Tests for User Story 1

- [x] T012 [P] [US1] Add LiveView test for alert rule schema-driven dropdown rendering and selection in `packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [x] T013 [P] [US1] Add LiveView test for report form schema-driven column/filter dropdown rendering in `packages/server/test/nixstasis_web/live/reports_live_test.exs`

### Implementation for User Story 1

- [x] T014 [US1] Integrate schema selector and condition field dropdown into alert builder modal in `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [x] T015 [US1] Replace report column/filter free-text path inputs with schema-derived dropdown controls in `packages/server/lib/nixstasis_web/live/reports/form_component.ex`
- [x] T016 [US1] Add shared helper component for rendering consistent schema option select controls in `packages/server/lib/nixstasis_web/components/core_components.ex`
- [x] T017 [US1] Update alert rule parameter shaping to persist selected schema keys instead of arbitrary typed paths in `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [x] T018 [US1] Update report config payload shaping to persist selected schema keys for fields/filters in `packages/server/lib/nixstasis_web/live/reports/form_component.ex`
- [x] T019 [US1] Add/adjust context-level validation tests for accepted schema keys in report querying path in `packages/server/test/nixstasis/reporting/query_builder_test.exs`

**Nixstasis**: User Story 1 works independently with schema-driven dropdown selection in both builders.

---

## Phase 4: User Story 2 - Keep Dropdowns in Sync with Schema Changes (Priority: P2)

**Goal**: Refresh options on schema/version changes, auto-clear invalid selections, and enforce reselection before save.

**Independent Test**: In either builder select schema A and a field, switch to schema B lacking that field, verify selection auto-clears with inline feedback and save remains blocked until corrected.

### Tests for User Story 2

- [x] T020 [P] [US2] Add alert LiveView test for schema switch option refresh and invalid-selection auto-clear in `packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [x] T021 [P] [US2] Add report LiveView test for schema switch option refresh and invalid-selection auto-clear in `packages/server/test/nixstasis_web/live/reports_live_test.exs`
- [x] T022 [P] [US2] Add LiveView regression test for preserving valid selections during non-schema form edits in `packages/server/test/nixstasis_web/live/reports_live_test.exs`
- [x] T023 [P] [US2] Add cross-builder LiveView test validating independent schema-version state between alert and report builders in `packages/server/test/nixstasis_web/live/alerts_live_test.exs` and `packages/server/test/nixstasis_web/live/reports_live_test.exs`

### Implementation for User Story 2

- [x] T024 [US2] Implement alert builder schema/version change event handlers and state refresh logic in `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [x] T025 [US2] Implement report builder schema/version change event handlers and state refresh logic in `packages/server/lib/nixstasis_web/live/reports/form_component.ex`
- [x] T026 [US2] Add inline reselection-required validation state and save blocking for invalidated alert selections in `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [x] T027 [US2] Add inline reselection-required validation state and save blocking for invalidated report selections in `packages/server/lib/nixstasis_web/live/reports/form_component.ex`
- [x] T028 [US2] Ensure non-schema input events do not mutate valid schema selections in `packages/server/lib/nixstasis_web/live/reports/form_component.ex`

**Nixstasis**: User Story 2 independently enforces schema-change consistency and invalid-selection correction.

---

## Phase 5: User Story 3 - Handle Missing or Empty Schema Safely (Priority: P3)

**Goal**: Provide clear empty/unavailable/access-lost behavior with fail-closed save blocking.

**Independent Test**: Simulate missing schema, unreadable schema, and access-loss cases; confirm dropdowns disable, feedback appears, and save is blocked until recovery.

### Tests for User Story 3

- [x] T029 [P] [US3] Add alert LiveView test coverage for missing/empty schema states and blocked save in `packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [x] T030 [P] [US3] Add report LiveView test coverage for missing/empty schema states and blocked save in `packages/server/test/nixstasis_web/live/reports_live_test.exs`
- [x] T031 [P] [US3] Add controller test coverage for schema access-loss and authorization failure responses in `packages/server/test/nixstasis_web/controllers/builder_schema_controller_test.exs`

### Implementation for User Story 3

- [x] T032 [US3] Implement alert builder empty-schema, unreadable-schema, and access-lost UI messaging/disable states in `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [x] T033 [US3] Implement report builder empty-schema, unreadable-schema, and access-lost UI messaging/disable states in `packages/server/lib/nixstasis_web/live/reports/form_component.ex`
- [x] T034 [US3] Implement fail-closed save guard that clears options and blocks persistence on schema access loss in `packages/server/lib/nixstasis/schema_options.ex` and `packages/server/lib/nixstasis_web/live/reports/form_component.ex`

**Nixstasis**: User Story 3 independently handles degraded schema states with clear feedback and safe behavior.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Finish performance, documentation, and end-to-end quickstart verification.

- [ ] T035 [P] Add telemetry/performance assertions for schema option load timing in `packages/server/test/nixstasis_web/live/alerts_live_test.exs` and `packages/server/test/nixstasis_web/live/reports_live_test.exs`
- [x] T036 Update schema-driven builder documentation in `packages/server/README.md` and `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/009-build-schema-dropdowns/quickstart.md`
- [ ] T037 Run quickstart verification flow and record implementation notes in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/009-build-schema-dropdowns/plan.md`
- [ ] T038 [P] Measure alert builder task-completion time against the 90-second target and record results in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/009-build-schema-dropdowns/quickstart.md`
- [ ] T039 [P] Measure report builder task-completion time against the 90-second target and record results in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/009-build-schema-dropdowns/quickstart.md`
- [x] T040 Define baseline metric queries for invalid-save rate, first-attempt completion, and support-ticket volume in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/009-build-schema-dropdowns/plan.md`
- [x] T041 [P] Add instrumentation events for invalid-save attempts and first-attempt completion in `packages/server/lib/nixstasis_web/live/alerts/index_live.ex` and `packages/server/lib/nixstasis_web/live/reports/form_component.ex`
- [x] T042 Add post-release validation checklist for SC-003/SC-004/SC-005 in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/009-build-schema-dropdowns/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies, start immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1, blocks all user stories.
- **Phase 3 (US1)**: Depends on Phase 2 completion.
- **Phase 4 (US2)**: Depends on Phase 2 completion; can proceed after US1 integration points exist.
- **Phase 5 (US3)**: Depends on Phase 2 completion; can proceed after US1 integration points exist.
- **Phase 6 (Polish)**: Depends on completion of desired user stories.

### User Story Dependencies

- **US1 (P1)**: No dependency on other user stories once foundational work is complete.
- **US2 (P2)**: Builds on US1 dropdown controls but remains independently testable.
- **US3 (P3)**: Builds on US1 dropdown controls and shared validation, independently testable.

### Within Each User Story

- Write tests first and verify they fail before implementation.
- Implement LiveView state/handlers before save-path integration.
- Complete inline validation and save-blocking before story closeout.

### Parallel Opportunities

- Foundational [P] tasks T005, T006, T008, T010 can run in parallel after T004.
- US1 tests T012 and T013 can run in parallel.
- US2 tests T020, T021, T022, and T023 can run in parallel.
- US3 tests T029, T030, and T031 can run in parallel.
- Polish tasks T035, T038, T039, and T041 can run in parallel with T036.

---

## Parallel Example: User Story 1

```bash
# Run US1 tests in parallel:
Task: "T012 [US1] Add LiveView test for alert rule schema-driven dropdown rendering and selection in packages/server/test/nixstasis_web/live/alerts_live_test.exs"
Task: "T013 [US1] Add LiveView test for report form schema-driven column/filter dropdown rendering in packages/server/test/nixstasis_web/live/reports_live_test.exs"
```

## Parallel Example: User Story 2

```bash
# Run US2 tests in parallel:
Task: "T020 [US2] Add alert LiveView test for schema switch option refresh and invalid-selection auto-clear in packages/server/test/nixstasis_web/live/alerts_live_test.exs"
Task: "T021 [US2] Add report LiveView test for schema switch option refresh and invalid-selection auto-clear in packages/server/test/nixstasis_web/live/reports_live_test.exs"
Task: "T022 [US2] Add LiveView regression test for preserving valid selections during non-schema form edits in packages/server/test/nixstasis_web/live/reports_live_test.exs"
Task: "T023 [US2] Add cross-builder LiveView test validating independent schema-version state between alert and report builders in packages/server/test/nixstasis_web/live/alerts_live_test.exs and packages/server/test/nixstasis_web/live/reports_live_test.exs"
```

## Parallel Example: User Story 3

```bash
# Run US3 degraded-state tests in parallel:
Task: "T029 [US3] Add alert LiveView test coverage for missing/empty schema states and blocked save in packages/server/test/nixstasis_web/live/alerts_live_test.exs"
Task: "T030 [US3] Add report LiveView test coverage for missing/empty schema states and blocked save in packages/server/test/nixstasis_web/live/reports_live_test.exs"
Task: "T031 [US3] Add controller test coverage for schema access-loss and authorization failure responses in packages/server/test/nixstasis_web/controllers/builder_schema_controller_test.exs"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 and Phase 2.
2. Complete Phase 3 (US1).
3. Validate US1 independently via dropdown rendering/selection tests.
4. Demo/deploy MVP with schema-driven selection replacing free-text paths.

### Incremental Delivery

1. Deliver US1 (schema-driven dropdowns).
2. Deliver US2 (schema-change refresh + invalidation handling).
3. Deliver US3 (missing/empty/access-loss fail-closed behavior).
4. Complete polish for performance/documentation validation.

### Parallel Team Strategy

1. Team completes Setup + Foundational together.
2. Then split by story:
   - Developer A: US1 primary UI integration.
   - Developer B: US2 schema-change state handling.
   - Developer C: US3 degraded-state and authorization-loss handling.
