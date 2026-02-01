---
description: "Implementation tasks for IoT Device Monitoring feature"
---

# Tasks: IoT Device Monitoring

**Input**: Design documents from `/specs/001-iot-device-monitoring/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/api.yaml

**Tests**: Tests are MANDATORY for APIs and complex logic (per Constitution).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Examine Elixir Phoenix 1.8+ project with LiveView 1.1+ in `.`
- [x] T002 Once you understand the structure of the Phoenix project remove the sample code
- [x] T004 Ensure Ecto is configured for Postgres and enable JSONB/GIN index support in `mix.exs` and `config/config.exs`
- [x] T005 Run `mix ecto.create` to create your database
- [x] T006 Setup basic Context structure (`Devices`, `Monitoring`, `Reporting`) in `lib/nixstasis/`
- [x] T007 Configure Phoenix Endpoint `check_origin` for Caddy/FRP trust in `config/runtime.exs`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T008 Create `devices` table migration with JSONB `schema_definition` and GIN index in `priv/repo/migrations/`
- [x] T009 Create `telemetry_events` table migration with JSONB payload and GIN index in `priv/repo/migrations/`
- [x] T010 Create `Device` schema with embedded schema validation support in `lib/nixstasis/devices/device.ex`
- [x] T011 Create `Telemetry` schema in `lib/nixstasis/monitoring/telemetry.ex`
- [x] T012 Setup basic API Pipeline in `lib/nixstasis_web/router.ex` (scope "/api/v1")
- [x] T013 Create `DeviceContext` with basic CRUD (no business logic yet) in `lib/nixstasis/devices.ex`

**Nixstasis**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Device Self-Registration & Grouping (Priority: P1)

**Goal**: Allow devices to register with dynamic schema and product key grouping

**Independent Test**: Register device with/without product key, verify DB persistence and rejection

### Tests for User Story 1 ⚠️

- [x] T014 [P] [US1] Create contract test for `POST /devices/register` in
      `test/nixstasis_web/controllers/device_controller_test.exs`
- [x] T015 [P] [US1] Create unit test for `Device` schema validation (product key required) in
      `test/nixstasis/devices/device_test.exs`

### Implementation for User Story 1

- [x] T016 [US1] Implement `register_device` logic in `Nixstasis.Devices` (handle schema validation) in
      `lib/nixstasis/devices.ex`
- [x] T017 [US1] Create `DeviceController.register/2` action in
      `lib/nixstasis_web/controllers/device_controller.ex`
- [x] T018 [US1] Implement JSONB schema validation helper (ensure `product` exists) in
      `lib/nixstasis/devices/schema_validator.ex`
- [x] T019 [US1] Add `product_key` extraction logic to Registration flow in `lib/nixstasis/devices.ex`

**Nixstasis**: Devices can register and are grouped by product key in DB

---

## Phase 4: User Story 2 - Device Approval Workflow (Priority: P1)

**Goal**: Gate registration via MAC address approval list

**Independent Test**: Register unapproved MAC -> Pending; Approve MAC; Register again -> Success

### Tests for User Story 2 ⚠️

- [x] T020 [P] [US2] Create integration test for Approval Workflow in `test/nixstasis/devices/approval_test.exs`

### Implementation for User Story 2

- [x] T021 [US2] Add `approval_status` field handling to `Device` changeset in `lib/nixstasis/devices/device.ex`
- [x] T022 [US2] Implement `approve_device` and `list_pending_devices` in `lib/nixstasis/devices.ex`
- [x] T023 [US2] Update `register_device` to check approval status (auto-reject/pending if unknown) in
      `lib/nixstasis/devices.ex`
- [x] T024 [US2] Ensure `Devices` context enforces `AuthCrunch` policies for admin actions (approvals).
- [x] T025 [US2] Create LiveView for Device Approval (Pending List) in
      `lib/nixstasis_web/live/devices/approval_live.ex`
- [x] T026 [US2] Create LiveView for Device Approval (Approved List + Add MAC) in
      `lib/nixstasis_web/live/devices/index_live.ex`

**Nixstasis**: Registration is now gated; Admin UI exists for approvals

---

## Phase 5: User Story 3 - Heartbeat & Command Delivery (Priority: P1)

**Goal**: Periodic check-ins and command delivery

**Independent Test**: Send Heartbeat -> OK; Queue Command -> Send Heartbeat -> Receive Command

### Tests for User Story 3 ⚠️

- [x] T027 [P] [US3] Create contract test for `POST /devices/heartbeat` in
      `test/nixstasis_web/controllers/heartbeat_controller_test.exs`
- [x] T028 [P] [US3] Create unit test for Command Queueing logic in `test/nixstasis/monitoring/command_queue_test.exs`

### Implementation for User Story 3

- [x] T029 [US3] Create `PendingCommand` schema and migration in `lib/nixstasis/devices/pending_command.ex`
- [x] T030 [US3] Implement `queue_command` and `pop_pending_commands` in `lib/nixstasis/devices.ex`
- [x] T031 [US3] Implement `heartbeat` logic (update last_seen, fetch commands) in `lib/nixstasis/monitoring.ex`
- [x] T032 [US3] Create `HeartbeatController.create/2` action in `lib/nixstasis_web/controllers/heartbeat_controller.ex`
- [x] T033 [US3] Implement `last_seen_at` update on heartbeat in `lib/nixstasis/devices.ex`
- [x] T033a [US3] Implement `RateLimiter` plug using Hammer or similar to enforce configurable limits per device token in `lib/nixstasis_web/plugs/rate_limiter.ex`

**Nixstasis**: Devices can check in and receive commands

---

## Phase 6: User Story 4 - Offline Device Alerts (Priority: P2)

**Goal**: Detect devices that stopped reporting

**Independent Test**: Register device -> Stop Heartbeat -> Wait Window -> Verify Alert Generated

### Tests for User Story 4 ⚠️

- [x] T034 [P] [US4] Create unit test for Offline Detection Logic in `test/nixstasis/monitoring/alert_worker_test.exs`

### Implementation for User Story 4

- [x] T035 [US4] Create `Alert` schema and migration in `lib/nixstasis/monitoring/alert.ex`
- [x] T036 [US4] Implement `check_offline_devices` function in `lib/nixstasis/monitoring.ex`
- [x] T037 [US4] Create GenServer/Oban worker for periodic offline checks in
      `lib/nixstasis/monitoring/offline_checker.ex`
- [x] T038 [US4] Create LiveView for Alerts Dashboard in `lib/nixstasis_web/live/alerts/index_live.ex`
- [x] T039 [US4] Implement Config UI for "Offline Window" duration in `lib/nixstasis_web/live/settings_live.ex`
- [x] T039a [US4] Implement Email dispatch for alerts using Swoosh in `lib/nixstasis/notifications/email.ex`
- [x] T039b [US4] Implement Webhook dispatch for alerts (POST payload) in `lib/nixstasis/notifications/webhook.ex`
- [x] T039c [US4] Implement UI form in Settings LiveView to configure Notification destinations (Email list, Webhook URL) in `lib/nixstasis_web/live/settings_live.ex`

**Nixstasis**: System auto-detects dead devices and shows alerts

---

## Phase 7: User Story 5 - Data-Driven Alerts (Priority: P3)

**Goal**: Custom alerts based on telemetry values

**Independent Test**: Define Rule (temp > 50) -> Send Telemetry (temp=60) -> Verify Alert

### Tests for User Story 5 ⚠️

- [x] T040 [P] [US5] Create unit test for Rule Evaluator in `test/nixstasis/monitoring/rule_evaluator_test.exs`

### Implementation for User Story 5

- [x] T041 [US5] Create `AlertRule` schema and migration in `lib/nixstasis/monitoring/alert_rule.ex`
- [x] T042 [US5] Implement `evaluate_telemetry` logic (match JSONB payload vs Rules) in `lib/nixstasis/monitoring.ex`
- [x] T043 [US5] Integrate `evaluate_telemetry` into Heartbeat/Telemetry ingestion flow in `lib/nixstasis/monitoring.ex`
- [x] T044 [US5] Create LiveView for creating/managing Alert Rules in `lib/nixstasis_web/live/alerts/rules_live.ex`

**Nixstasis**: Users can define dynamic alerts on JSON data

---

## Phase 8: User Story 6 - Custom Reports & Overviews (Priority: P3)

**Goal**: Cross-product reporting using dynamic schema fields

**Independent Test**: Create Report (Product A.temp + Product B.voltage) -> View Report -> See data

### Tests for User Story 6 ⚠️

- [x] T045 [P] [US6] Create unit test for Dynamic Query Builder in `test/nixstasis/reporting/query_builder_test.exs`

### Implementation for User Story 6

- [x] T046 [US6] Create `CustomReport` schema (stores query config) in `lib/nixstasis/reporting/custom_report.ex`
- [x] T047 [US6] Implement Ecto Query builder for JSONB path extraction in `lib/nixstasis/reporting.ex`
- [x] T048 [US6] Create LiveView for Report Builder UI (Field Selector) in`lib/nixstasis_web/live/reports/builder_live.ex`
- [ ] T048a [US6] Implement conflict resolution UI/logic in Report Builder to handle fields with differing types (per FR-016a) in `lib/nixstasis_web/live/reports/builder_live.ex`
- [x] T049 [US6] Create LiveView for Report Viewer (Table/Chart) in `lib/nixstasis_web/live/reports/show_live.ex`

**Nixstasis**: Dynamic reporting across device types

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements, docs, and final validation

- [x] T050 [P] Update Quickstart docs with final API examples in `specs/001-iot-device-monitoring/quickstart.md`
- [x] T051 Refactor `DeviceController` to use `FallbackController` for errors in
      `lib/nixstasis_web/controllers/fallback_controller.ex`
- [x] T052 Optimize GIN indexes for specific common search paths in `priv/repo/migrations/` (optional tuning)
- [x] T053 [P] Add DaisyUI theme switching support in `lib/nixstasis_web/components/layouts/root.html.heex`
- [x] T054 Run full integration test suite and verify no regressions

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Blocks EVERYTHING
- **US1 (Registration)**: Blocks US2, US3
- **US2 (Approval)**: Blocks full usage of US3 (Heartbeat needs approval)
- **US3 (Heartbeat)**: Blocks US4 (Offline Alerts need heartbeats), US5 (Data Alerts need telemetry)
- **US6 (Reporting)**: Independent, but needs Telemetry data (US3 context)

### Parallel Opportunities

- **US4 (Offline Alerts)** and **US5 (Data Alerts)** can be built in parallel after US3
- **US6 (Reporting)** can be built in parallel with US4/US5
- **Frontend (LiveView)** and **Backend (Contexts)** within each story can often be parallelized

## Implementation Strategy

### MVP (Stories 1, 2, 3)

1. Complete Setup & Foundation
2. Implement Registration (US1) + Approval (US2)
3. Implement Heartbeat (US3)
4. **Deploy MVP**: Devices can register, be approved, and report status.

### Increment 1 (Monitoring)

1. Add Offline Alerts (US4)
2. Add Data Rules (US5)

### Increment 2 (Analytics)

1. Add Custom Reporting (US6)
