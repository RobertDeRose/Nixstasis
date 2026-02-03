# Tasks: Rewrite Client in Go

**Input**: Design documents from `/specs/004-rewrite-client-go/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- - Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Initialize Go module and project structure with `go.mod`, `cmd/nixstasis/main.go`, `internal/`
- [x] T002 [P] Configure standard Go linting (golangci-lint)
- [x] T003 [P] Implement `internal/config` to load `/etc/nixstasis/config.yaml` with Viper/Koanf (supports FR-010)
- [x] T004 [P] Implement structured logging in `internal/logging` (supports SC-005)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Create `internal/identity` package with `DeviceIdentity` struct (matches data-model.md)
- [ ] T006 Create `internal/plugin` package with `PluginManifest` and `TelemetryPayload` structs (include `DeviceStatus` field)
- [x] T007 Create `internal/transport` package for HTTP client wrapper (supports FR-008)
- [x] T008 [P] Implement `internal/frp` package skeleton for remote access management

**Nixstasis**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Device Identity & Registration (Priority: P1) 🎯 MVP

**Goal**: Device automatically registers on boot and persists UUID.

**Independent Test**: Delete local ID file, restart service, verify new ID is negotiated and saved.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T009 [P] [US1] Unit test for MAC detection in `internal/identity/detect_test.go`
- [x] T010 [P] [US1] Integration test for Registration API flow in `internal/transport/register_test.go` (mock server)

### Implementation for User Story 1

- [x] T011 [P] [US1] Implement MAC/IP detection logic in `internal/identity/detect.go` (FR-002)
- [x] T012 [P] [US1] Implement ID persistence (Load/Save) in `internal/identity/store.go` (FR-003)
- [x] T013 [US1] Implement `RegisterDevice` in `internal/transport/client.go` using `contracts/device-api.yaml`
- [x] T014 [US1] Implement `nixstasis register` subcommand in `cmd/nixstasis/register.go` orchestrating T011-T013
- [x] T015 [US1] Add error handling and retries for registration failures (Edge Case: Network Flapping)

**Nixstasis**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Plugin-Based Telemetry Polling (Priority: P1)

**Goal**: Execute external plugins, merge JSON output, and report telemetry.

**Independent Test**: Create dummy plugin with manifest, run polling loop, verify merged payload sent to mock API.

### Tests for User Story 2 ⚠️

- [x] T016 [P] [US2] Unit test for `PluginManifest` parsing in `internal/plugin/manifest_test.go`
- [x] T017 [P] [US2] Unit test for JSON merging logic in `internal/plugin/merge_test.go` (Edge Case: Conflicts)

### Implementation for User Story 2

- [x] T018 [P] [US2] Implement plugin discovery (FHS paths) in `internal/plugin/discovery.go` (FR-004)
- [x] T019 [P] [US2] Implement `manifest.json` parsing in `internal/plugin/manifest.go`
- [x] T020 [US2] Implement parallel execution engine in `internal/plugin/executor.go` (FR-005, SC-004 timeout)
- [x] T021 [US2] Implement JSON deep merge logic in `internal/plugin/merge.go` (FR-006)
- [x] T022 [US2] Implement `Poll` method in `internal/transport/client.go` to send merged payload (include dynamic `DeviceStatus` and Plugin Metadata)
- [x] T023 [US2] Implement `nixstasis poll` subcommand in `cmd/nixstasis/poll.go` (Main Loop SC-002)

**Nixstasis**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Remote Access Control (Priority: P2)

**Goal**: Start/Stop `frpc` tunnel based on API response.

**Independent Test**: Mock API returns `remote_access_requested: true`, verify `frpc` starts.

### Tests for User Story 3 ⚠️

- [x] T024 [P] [US3] Unit test for FRP timeout logic in `internal/frp/manager_test.go`

### Implementation for User Story 3

- [x] T025 [P] [US3] Implement `Start/Stop` logic in `internal/frp/manager.go` wrapping `os/exec` (FR-009)
- [x] T026 [US3] Integrate FRP check into Polling Loop in `cmd/nixstasis/poll.go`
- [ ] T027 [US3] Implement lifecycle hooks (notify API of connection string) in `internal/frp/manager.go`

**Nixstasis**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T028 [P] Create `Makefile` for building binaries
- [x] T029 Create packaging scripts for `.deb` and `.tar.gz` (FR-011)
- [x] T030 Create systemd unit file `nixstasis-client.service`
- [x] T031 Validate `quickstart.md` steps against built artifacts

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
- **User Story 2 (P1)**: Can start after Foundational (Phase 2) - May integrate with US1 but should be independently testable
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - May integrate with US1/US2 but should be independently testable
