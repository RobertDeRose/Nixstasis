# Tasks: Server-Client E2E Tests

**Input**: Feature design and current E2E module docs.

## Path Conventions

- Monorepo: `packages/server/...` for Phoenix server, `packages/client/...` for Go client
- Feature docs: `docs/src/features/server-client-e2e-tests/...`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create E2E harness directories and scaffold files in packages/client/scripts/e2e/README.md and packages/server/test/e2e/.gitkeep
- [X] T002 Add E2E configuration defaults to packages/server/config/test.exs
- [X] T003 P Add client E2E config example in packages/client/scripts/e2e/config.example.yaml

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create E2E database migration in packages/server/priv/repo/migrations/20260209235459_create_e2e_runs.exs
- [X] T005 Implement E2E schemas/context in packages/server/lib/nixstasis/e2e.ex and packages/server/lib/nixstasis/e2e/*.ex
- [X] T006 P Implement version pairing validator in packages/server/lib/nixstasis/e2e/versioning.ex
- [X] T007 P Add synthetic data policy validator in packages/server/lib/nixstasis/e2e/data_policy.ex
- [X] T008 P Add unit tests for data policy in packages/server/test/nixstasis/e2e/data_policy_test.exs
- [X] T009 P Implement log storage helper in packages/server/lib/nixstasis/e2e/log_store.ex
- [X] T010 P Implement environment reset/seed helpers in packages/server/priv/e2e/seed.exs and packages/server/test/support/e2e_reset.exs
- [X] T011 P Add client E2E runner core package skeleton in packages/client/internal/e2e/runner.go and packages/client/internal/e2e/config.go

**Nixstasis**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Full Release Validation (Priority: P1) 🎯 MVP

**Goal**: Run a full E2E suite between client and server and produce a summary report.

**Independent Test**: Trigger a full run and verify all critical journeys execute with a pass/fail summary.

### Tests for User Story 1 ⚠️

- [X] T012 P US1 Add BDD controller tests for listing/creating runs in packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs
- [X] T013 P US1 Add BDD controller test for GET /e2e/runs/{run_id} in packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs
- [X] T014 P US1 Add BDD controller test for POST /e2e/runs/{run_id}/cancel in packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs
- [X] T015 P US1 Add runner unit tests for full-suite execution in packages/client/internal/e2e/runner_test.go
- [X] T016 P US1 Add BDD tests for precondition failures in packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs

### Implementation for User Story 1

- [X] T017 US1 Implement E2E run controller and routes in packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex and packages/server/lib/nixstasis_web/router.ex
- [X] T018 US1 Implement run creation + metadata persistence in packages/server/lib/nixstasis/e2e.ex
- [X] T019 US1 Enforce synthetic-only policy during run creation in packages/server/lib/nixstasis/e2e.ex
- [X] T020 US1 Add fail-fast precondition checks with actionable messages in packages/server/lib/nixstasis/e2e.ex
- [X] T021 US1 Implement summary report generation in packages/server/lib/nixstasis/e2e/reporting.ex
- [X] T022 US1 Implement full-suite harness script in packages/client/scripts/e2e/run
- [X] T023 US1 Define critical journey specs in packages/client/scripts/e2e/journeys/*.yaml

**Nixstasis**: User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Targeted Journey Verification (Priority: P2)

**Goal**: Run a selected subset of journeys with validation for invalid selections.

**Independent Test**: Trigger a run for a single journey and confirm only that journey executes; invalid selections fail fast.

### Tests for User Story 2 ⚠️

- [X] T024 P US2 Add BDD tests for journey selection validation in packages/server/test/nixstasis/e2e/journey_selection_test.exs
- [X] T025 P US2 Add journey filtering tests in packages/client/internal/e2e/selector_test.go

### Implementation for User Story 2

- [X] T026 US2 Implement journey selection/filtering in packages/client/internal/e2e/selector.go
- [X] T027 US2 Update harness args parsing for --journey/--journeys in packages/client/scripts/e2e/run
- [X] T028 US2 Enforce journey_ids subset validation in packages/server/lib/nixstasis/e2e.ex

**Nixstasis**: User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Repeatable, Auditable Results (Priority: P3)

**Goal**: Ensure runs are repeatable with reset data and auditable results/metadata.

**Independent Test**: Run the same suite twice with reset data and compare consistent results with recorded metadata.

### Tests for User Story 3 ⚠️

- [X] T029 P US3 Add BDD tests for results + metadata retrieval in packages/server/test/nixstasis_web/controllers/e2e_run_result_controller_test.exs
- [X] T030 P US3 Add log storage tests in packages/server/test/nixstasis/e2e/log_store_test.exs

### Implementation for User Story 3

- [X] T031 US3 Implement results controller and routes in packages/server/lib/nixstasis_web/controllers/e2e_run_result_controller.ex and packages/server/lib/nixstasis_web/router.ex
- [X] T032 US3 Persist per-journey results/log refs in packages/server/lib/nixstasis/e2e.ex and packages/server/lib/nixstasis/e2e/log_store.ex
- [X] T033 US3 Wire environment reset/seed into run lifecycle in packages/server/lib/nixstasis/e2e.ex

**Nixstasis**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T034 P Capture run duration + report latency in packages/server/lib/nixstasis/e2e/reporting.ex
- [X] T035 P Add run timing tests in packages/server/test/nixstasis/e2e/reporting_test.exs
- [X] T036 P Capture per-journey duration in packages/client/internal/e2e/runner.go and tests in packages/client/internal/e2e/runner_test.go
- [X] T037 P Add flaky-rate calculation in packages/server/lib/nixstasis/e2e/metrics.ex with tests in packages/server/test/nixstasis/e2e/metrics_test.exs
- [X] T038 P Update README/module docs with final runner flags.
- [X] T039 P Document E2E runner usage in packages/client/README.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independent but builds on shared harness
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Independent but uses shared run metadata

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models/context before controllers/endpoints
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- Setup tasks marked P can run in parallel
- Foundational tasks marked P can run in parallel (within Phase 2)
- Once Foundational phase completes, all user stories can start in parallel (if team capacity allows)
- Tests for a user story marked P can run in parallel

---

## Parallel Example: User Story 1

```bash
Task: "Add BDD controller tests for listing/creating runs in packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs"
Task: "Add runner unit tests for full-suite execution in packages/client/internal/e2e/runner_test.go"
Task: "Define critical journey specs in packages/client/scripts/e2e/journeys/*.yaml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Demo
3. Add User Story 2 → Test independently → Demo
4. Add User Story 3 → Test independently → Demo
5. Each story adds value without breaking previous stories
