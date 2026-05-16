# Tasks: Starlark Script System

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Add Starlark and JSON Schema dependencies to packages/client/go.mod
- [X] T002 P Add MQTT client dependency to packages/client/go.mod
- [X] T003 P Create scripting package scaffold in packages/client/internal/script/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

- [X] T004 Define `stary` front-matter struct and parser in packages/client/internal/script/format.go
- [X] T005 P Implement Starlark runtime wrapper (thread, globals, timeouts) in packages/client/internal/script/runtime.go
- [X] T006 P Implement JSON Schema validator adapter in packages/client/internal/script/validator.go
- [X] T007 Implement script discovery (directories, listing) in packages/client/internal/script/discovery.go
- [X] T008 Implement script execution result types and error/warning models in packages/client/internal/script/types.go
- [X] T009 Implement telemetry report mapper to match existing payload structure in packages/client/internal/script/report.go
- [X] T010 Implement unit tests for front-matter parsing and schema validation in packages/client/internal/script/format_test.go
- [X] T011 Implement unit tests for runtime timeout and warning thresholds in packages/client/internal/script/runtime_test.go
- [X] T012 Define script execution result envelope (status, validation_status, warnings) in packages/client/internal/script/types.go
- [X] T013 P Add unit tests for result envelope mapping in packages/client/internal/script/report_test.go

**Nixstasis**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Run a Stary Script (Priority: P1) 🎯 MVP

**Goal**: Execute `stary` scripts with schema-validated output and return results for telemetry

**Independent Test**: Provide a valid `stary` file with YAML front-matter and run it; confirm a validated output is produced.

### Tests for User Story 1

- [X] T014 P US1 Add BDD-style Given/When/Then behavior test for successful `stary` execution in packages/client/internal/script/executor_test.go
- [X] T015 P US1 Add BDD-style Given/When/Then behavior test for script selection by name/path in packages/client/internal/script/discovery_test.go

### Implementation for User Story 1

- [X] T016 P US1 Implement `stary` executor to parse, run, and validate output in packages/client/internal/script/executor.go
- [X] T017 US1 Integrate script execution into polling flow in packages/client/cmd/nixstasis/poll.go
- [X] T018 US1 Replace plugin discovery/execution usage with script discovery in packages/client/internal/plugin/ (remove/retire)

**Nixstasis**: User Story 1 should be fully functional and independently testable

---

## Phase 4: User Story 2 - Detect and Explain Script Errors (Priority: P2)

**Goal**: Surface clear error messages for invalid front-matter, execution failures, schema validation issues, and timeouts

**Independent Test**: Run a script with invalid YAML front-matter or mismatched output and verify error messaging and rejection behavior.

### Tests for User Story 2

- [X] T019 P US2 Add BDD-style Given/When/Then behavior tests for invalid front-matter and schema mismatch in packages/client/internal/script/validation_test.go
- [X] T020 P US2 Add BDD-style Given/When/Then behavior tests for execution timeout and error mapping in packages/client/internal/script/executor_test.go

### Implementation for User Story 2

- [X] T021 US2 Implement error mapping with script name and reason in packages/client/internal/script/errors.go
- [X] T022 US2 Emit warnings for slow scripts and include in report in packages/client/internal/script/report.go
- [X] T023 US2 Ensure telemetry payload captures script errors in packages/client/internal/script/report.go

**Nixstasis**: User Stories 1 and 2 should both work independently

---

## Phase 5: User Story 3 - Discover, Install, and Remove Scripts (Priority: P3)

**Goal**: Support list, install, and remove commands for managing `stary` scripts

**Independent Test**: Provide a folder with multiple `stary` files and confirm the user can list, install, and remove scripts as expected.

### Tests for User Story 3

- [X] T024 P US3 Add BDD-style Given/When/Then CLI tests for list/install/remove in packages/client/cmd/nixstasis/scripts_test.go

### Implementation for User Story 3

- [X] T025 P US3 Implement `list_scripts` command in packages/client/cmd/nixstasis/list_scripts.go
- [X] T026 P US3 Implement `install_script` command in packages/client/cmd/nixstasis/install_script.go
- [X] T027 P US3 Implement `remove_script` command in packages/client/cmd/nixstasis/remove_script.go
- [X] T028 US3 Wire commands into CLI root in packages/client/cmd/nixstasis/main.go

**Nixstasis**: All user stories should now be independently functional

---

## Phase 6: User Story 4 - Test and REPL for Scripts (Priority: P4)

**Goal**: Provide CLI tooling for `test_script` and a Starlark REPL with builtins

**Independent Test**: Run `test_script` against a valid script and verify pretty-printed YAML output; start `repl` and call a builtin.

### Tests for User Story 4

- [X] T029 P US4 Add BDD-style Given/When/Then CLI tests for `test_script` YAML output formatting in packages/client/cmd/nixstasis/test_script_test.go
- [X] T030 P US4 Add BDD-style Given/When/Then CLI tests for REPL startup and builtins availability in packages/client/cmd/nixstasis/repl_test.go
- [X] T031 P US4 Add BDD-style Given/When/Then CLI tests for `test_script` failure exit behavior (no YAML output) in packages/client/cmd/nixstasis/test_script_test.go

### Implementation for User Story 4

- [X] T032 P US4 Implement `test_script` command (path arg, YAML pretty-printed output) in packages/client/cmd/nixstasis/test_script.go
- [X] T033 P US4 Implement `repl` command with builtins in packages/client/cmd/nixstasis/repl.go
- [X] T034 US4 Wire `test_script` and `repl` into CLI root in packages/client/cmd/nixstasis/main.go

**Nixstasis**: All user stories should now be independently functional

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T035 P Add built-in `pub_and_get` MQTT function for Starlark in packages/client/internal/script/builtins_mqtt.go
- [X] T036 P Add built-in OS command execution function with blacklist in packages/client/internal/script/builtins_exec.go
- [X] T037 P Add unit tests for MQTT `pub_and_get` filtering in packages/client/internal/script/builtins_mqtt_test.go
- [X] T038 P Add unit tests for OS command blacklist enforcement in packages/client/internal/script/builtins_exec_test.go
- [X] T039 P Define heartbeat command request/response types (command_id, type, payload, status, output, error) in packages/client/internal/transport/client.go
- [X] T040 Implement command execution coordinator (parallel execution, duplicate handling, 5s timeout, 1s result send window) in packages/client/internal/commands/handler.go
- [X] T041 Wire heartbeat command processing and results API call into polling loop in packages/client/cmd/nixstasis/poll.go
- [X] T042 P Add BDD-style Given/When/Then unit tests for command timeout/aggregation/duplicate handling in packages/client/internal/commands/handler_test.go
- [X] T043 P Add BDD-style Given/When/Then behavior test for poll command handling response flow in packages/client/cmd/nixstasis/poll_test.go
- [X] T044 P Update CLI docs with `test_script` and `repl` behavior.
- [X] T045 Update client README with `test_script` and `repl` usage.
- [X] T046 Run validation against updated CLI behavior.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - no dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational - may integrate with US1 but independently testable
- **User Story 3 (P3)**: Can start after Foundational - independently testable
- **User Story 4 (P4)**: Can start after Foundational - independently testable

### Parallel Opportunities

- T001 and T002 can run in parallel
- T004, T005, T006, T007, T008, T009 can run in parallel after setup
- T014 and T015 can run in parallel
- T019 and T020 can run in parallel
- T025, T026, T027 can run in parallel
- T029, T030, T031 can run in parallel
- T035 and T036 can run in parallel, along with their corresponding tests T037/T038
- T039 and T042 can run in parallel once foundational work is done

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate P1 independently

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → MVP
3. Add User Story 2 → Test independently
4. Add User Story 3 → Test independently
5. Add User Story 4 → Test independently
6. Complete Polish tasks
