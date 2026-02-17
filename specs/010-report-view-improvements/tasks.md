# Tasks: Report View Improvements

**Input**: Design documents from `/specs/010-report-view-improvements/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are MANDATORY for APIs and complex logic (per Constitution). Include test tasks unless explicitly exempted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Align report feature scaffolding and test data for upcoming story work

- [X] T001 Document feature scope and interaction expectations in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/README.md
- [X] T002 Add reusable report test fixtures for sortable/filterable datasets in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/support/fixtures/report_fixtures.ex
- [X] T003 [P] Add helper assertions for report row ordering and filter outcomes in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/support/report_assertions.ex

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build shared sort/filter primitives required by list and detail report views

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create shared comparator and coercion utilities for report tables in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis/reporting/table_filters.ex
- [X] T005 [P] Add unit tests for comparator mapping (`gt`,`gte`,`eq`,`lte`,`lt`) and type coercion edge cases in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis/reporting/table_filters_test.exs
- [X] T006 Extend reporting context with list-level sort/filter query helpers in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis/reporting.ex
- [X] T007 [P] Add context tests for custom report list sort/filter behavior in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis/reporting/custom_report_list_test.exs
- [X] T008 Extend query execution pipeline to accept results sort/filter state in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis/reporting/query_builder.ex
- [X] T009 [P] Add query-builder tests for report result sorting/filtering and invalid value handling in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis/reporting/query_builder_test.exs

**Nixstasis**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Readable Report Results (Priority: P1) 🎯 MVP

**Goal**: Make report result tables sortable/filterable with clear behavior and robust validation

**Independent Test**: Open an existing custom report and verify sorting by visible columns plus filtering with operators `>`, `>=`, `==`, `<=`, `<` without breaking render flow.

### Tests for User Story 1

- [X] T010 [P] [US1] Add LiveView test coverage for detail-table column sorting controls in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs
- [X] T011 [P] [US1] Add LiveView test coverage for detail-table filter operators and validation messaging in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs
- [X] T012 [P] [US1] Add LiveView tests for unauthorized access to report detail sorting/filtering controls in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs

### Implementation for User Story 1

- [X] T013 [US1] Implement report detail sort/filter state assigns and events in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/show_live.ex
- [X] T014 [US1] Apply shared table filter/comparator logic when loading report detail results in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/show_live.ex
- [X] T015 [US1] Add report detail filter UI controls (column, operator, value) with clear empty/error states in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/show_live.ex
- [X] T016 [US1] Add sort affordances to report detail table headers and preserve active sort state in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/show_live.ex
- [X] T017 [US1] Enforce permission checks for report detail sorting/filtering interactions in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/show_live.ex

**Nixstasis**: User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Faster Report Navigation (Priority: P2)

**Goal**: Improve Custom Reports list navigation with sortable/filterable columns and clear row actions (`View`, `Edit`, `Delete`)

**Independent Test**: From `/reports`, sort/filter rows, open edit modal from row action, and delete a report only after confirmation.

### Tests for User Story 2

- [X] T018 [P] [US2] Add LiveView tests for custom report list sorting/filtering interactions in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs
- [X] T019 [P] [US2] Add LiveView tests for row actions (`View`,`Edit`,`Delete`) and delete confirmation flows in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs
- [X] T020 [P] [US2] Add LiveView tests to assert edit action preloads query modal with existing config and persists updates in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs
- [X] T021 [P] [US2] Add LiveView tests for unauthorized list actions (`View`,`Edit`,`Delete`) and restricted list filtering behavior in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs

### Implementation for User Story 2

- [X] T022 [US2] Add list-level sort/filter params and assign handling for reports index in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/index_live.ex
- [X] T023 [US2] Implement list table sort/filter controls and bind them to reporting context queries in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/index_live.ex
- [X] T024 [US2] Replace current single row action with clearly styled `View`, `Edit`, and `Delete` action links in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/index_live.ex
- [X] T025 [US2] Implement delete-confirmation modal state/events and wire confirmed deletion to reporting context in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/index_live.ex
- [X] T026 [US2] Add edit route/action handling so row `Edit` opens existing query modal with selected report in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/index_live.ex
- [X] T027 [US2] Add or adjust shared action-link styling classes for clarity and destructive emphasis in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/components/core_components.ex
- [X] T028 [US2] Enforce permission checks for report list sort/filter and row actions in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/index_live.ex

**Nixstasis**: User Stories 1 and 2 should be independently functional

---

## Phase 5: User Story 3 - Reliable View Preferences (Priority: P3)

**Goal**: Preserve user report-view context and recover safely when stored view state becomes invalid

**Independent Test**: Set sort/filter preferences, navigate away and back, and verify state restoration or safe fallback with user feedback.

### Tests for User Story 3

- [X] T029 [P] [US3] Add LiveView tests for persistence of report list/detail sort-filter state during navigation in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs
- [X] T030 [P] [US3] Add LiveView tests for invalid restored state fallback messaging in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/reports_live_test.exs

### Implementation for User Story 3

- [X] T031 [US3] Persist report list sort/filter state to saved user view preferences and rehydrate in mount/handle_params in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/index_live.ex
- [X] T032 [US3] Persist report detail sort/filter state to saved user view preferences and rehydrate on reload in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/show_live.ex
- [X] T033 [US3] Add invalid-state detection and safe default fallback messaging for restored sort/filter state in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/show_live.ex
- [X] T034 [US3] Implement reporting-context persistence API for per-user report view preferences in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis/reporting.ex

**Nixstasis**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validate end-to-end quality, performance, and documentation across all stories

- [X] T035 [P] Perform contract conformance review for custom report list/results interactions (reference-only contract) in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/010-report-view-improvements/contracts/custom-reports-view.openapi.yaml
- [X] T036 Capture pre-change baseline median report review time for SC-002 in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/010-report-view-improvements/quickstart.md
- [X] T037 Run quickstart validation scenarios and record outcomes in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/010-report-view-improvements/quickstart.md
- [X] T038 [P] Perform final UX copy/style consistency pass for report list/detail actions and messages in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/index_live.ex
- [X] T039 Capture release-note summary for report view improvements in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/README.md
- [X] T040 [P] Define support-ticket baseline and post-release comparison method for SC-004 in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/010-report-view-improvements/quickstart.md
- [X] T041 Capture pre-release support-ticket baseline values for report-view issues in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/010-report-view-improvements/quickstart.md
- [X] T042 Mark custom-reports OpenAPI contract as deferred/reference-only for this feature increment in /Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/010-report-view-improvements/contracts/custom-reports-view.openapi.yaml

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational; no dependency on other stories
- **User Story 2 (P2)**: Can start after Foundational; depends only on shared sort/filter primitives from Phase 2
- **User Story 3 (P3)**: Can start after Foundational; relies on completed sort/filter interactions from US1 and US2

### Within Each User Story

- Tests for complex logic/UI interactions are written before implementation and must fail first
- Shared context/query behavior before LiveView UI binding
- State restoration and fallback after base interactions are stable

### Parallel Opportunities

- T003 can run in parallel with T001-T002
- T005, T007, and T009 can run in parallel after T004/T006/T008 scaffolding exists
- In US1, T010 and T011 can run in parallel
- In US1, T012 can run in parallel with T010 and T011
- In US2, T018, T019, T020, and T021 can run in parallel
- In US3, T029 and T030 can run in parallel
- In Polish, T035, T038, and T040 can run in parallel with T037

---

## Parallel Example: User Story 2

```bash
# Launch US2 tests in parallel
Task: "T018 [US2] LiveView tests for list sorting/filtering in packages/server/test/nixstasis_web/live/reports_live_test.exs"
Task: "T019 [US2] LiveView tests for row actions and delete confirmation in packages/server/test/nixstasis_web/live/reports_live_test.exs"
Task: "T020 [US2] LiveView tests for edit-modal preload/save in packages/server/test/nixstasis_web/live/reports_live_test.exs"

# Then implement independent UI pieces in parallel where possible
Task: "T024 [US2] Add action links in packages/server/lib/nixstasis_web/live/reports/index_live.ex"
Task: "T027 [US2] Update shared action-link styles in packages/server/lib/nixstasis_web/components/core_components.ex"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate report detail sorting/filtering independently

### Incremental Delivery

1. Deliver US1 (report detail readability via sort/filter)
2. Deliver US2 (list navigation/actions/edit/delete confirmation)
3. Deliver US3 (view-state persistence and recovery)
4. Finish with Polish and quickstart validation

### Parallel Team Strategy

1. Team aligns on Phase 1 and Phase 2 shared primitives
2. After foundation is complete:
   - Developer A: US1 detail table behavior
   - Developer B: US2 index actions and modal/delete flows
   - Developer C: US3 state persistence/fallback behavior

---

## Notes

- [P] tasks indicate no direct file conflict and can be run concurrently with proper sequencing
- [US#] labels map implementation and tests directly to user story outcomes
- Commit in small logical increments per phase or per completed task group
- Re-run targeted tests after each story checkpoint before moving to next phase
