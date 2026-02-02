# Tasks: IoT Dashboard Homepage

**Feature**: `002-add-dashboard-home`
**Status**: Pending

## Phase 1: Setup
*Goal: Initialize dashboard structure and shared components.*

- [x] T001 Create DashboardStats struct module in `lib/nixstasis/dashboard/stats.ex`
- [x] T002 Create Dashboard context module in `lib/nixstasis/dashboard.ex`
- [x] T003 Create dashboard LiveView file in `lib/nixstasis_web/live/dashboard_live/index.ex`
- [x] T004 Create dashboard LiveView template in `lib/nixstasis_web/live/dashboard_live/index.html.heex`
- [x] T005 Create dashboard LiveView test file in `test/nixstasis_web/live/dashboard_live_test.exs` using BDD style (Given/When/Then)
- [x] T006 Add route for dashboard (root path) in `lib/nixstasis_web/router.ex`

## Phase 2: Foundational
*Goal: Implement backend aggregation logic and Context API.*

- [x] T007 Implement `Nixstasis.Devices.count_all/0` in `lib/nixstasis/devices.ex`
- [x] T008 [P] Implement `Nixstasis.Devices.count_by_status/1` in `lib/nixstasis/devices.ex`
- [x] T009 [P] Implement `Nixstasis.Devices.count_pending_approvals/0` in `lib/nixstasis/devices.ex`
- [x] T010 [P] Implement `Nixstasis.Alerts.count_active/0` in `lib/nixstasis/alerts.ex`
- [x] T011 Create unit tests for new count functions in `test/nixstasis/devices_test.exs`
- [x] T012 Create unit tests for new alert count functions in `test/nixstasis/alerts_test.exs`
- [x] T013 Implement `Nixstasis.Dashboard.get_vital_stats/0` aggregating data in `lib/nixstasis/dashboard.ex`

## Phase 3: User Story 1 - View Vital Statistics
*Goal: Display real-time fleet health overview.*

- [x] T014 [US1] Implement `mount/3` in `lib/nixstasis_web/live/dashboard_live/index.ex` to fetch stats
- [x] T015 [US1] Create stats card component in `lib/nixstasis_web/components/layouts/stats_card.ex` (or embedded in `core_components.ex`)
- [x] T016 [US1] Render stats grid in `lib/nixstasis_web/live/dashboard_live/index.html.heex`
- [x] T017 [US1] Implement PubSub subscription for `devices` and `alerts` topics in `lib/nixstasis_web/live/dashboard_live/index.ex`
- [x] T018 [US1] Implement `handle_info/2` in `lib/nixstasis_web/live/dashboard_live/index.ex` to refresh specific stats (e.g. refetch count) upon receiving PubSub events
- [x] T019 [US1] Add test case: Verify initial stats rendering in `test/nixstasis_web/live/dashboard_live_test.exs` using BDD style
- [x] T020 [US1] Add test case: Verify real-time updates via PubSub in `test/nixstasis_web/live/dashboard_live_test.exs` using BDD style

## Phase 4: User Story 2 - Navigation to Core Features
*Goal: Enable navigation from dashboard to management views.*

- [x] T021 [US2] Add "Manage Devices" link button to dashboard template in `lib/nixstasis_web/live/dashboard_live/index.html.heex`
- [x] T022 [US2] Add "Pending Approvals" link button to dashboard template in `lib/nixstasis_web/live/dashboard_live/index.html.heex`
- [x] T023 [US2] Add "View Alerts" link button to dashboard template in `lib/nixstasis_web/live/dashboard_live/index.html.heex`
- [x] T024 [US2] Add "Reports" link button to dashboard template in `lib/nixstasis_web/live/dashboard_live/index.html.heex`
- [x] T025 [US2] Add test case: Verify navigation links exist and point to correct paths in `test/nixstasis_web/live/dashboard_live_test.exs` using BDD style
- [x] T026 [US2] Make stat cards clickable (link to filtered views using URL params, e.g. `?status=offline`) in `lib/nixstasis_web/live/dashboard_live/index.html.heex`

## Phase 5: Polish & Cross-Cutting
*Goal: Refine UX and ensure robust error handling.*

- [x] T027 Style dashboard grid with DaisyUI classes for responsiveness in `lib/nixstasis_web/live/dashboard_live/index.html.heex`
- [x] T028 Add loading state/placeholder while stats fetch in `lib/nixstasis_web/live/dashboard_live/index.html.heex`
- [x] T029 Verify manual verification steps from `quickstart.md`

## Dependencies

1. **Phase 1 (Setup)**: Blocks Phase 2
2. **Phase 2 (Foundational)**: Blocks Phase 3
3. **Phase 3 (US1)**: Blocks Phase 4 (Navigation builds on UI structure)
4. **Phase 4 (US2)**: Independent of US1 logic but dependent on US1 UI layout
5. **Phase 5 (Polish)**: Runs last

## Implementation Strategy

- **MVP Scope**: Complete Phase 1, 2, and 3 (US1). This delivers the core value of "Real-time Vital Stats".
- **Incremental Delivery**:
  1. Backend aggregation logic (Phase 2)
  2. Static Dashboard UI (Phase 3 first half)
  3. Real-time wiring (Phase 3 second half)
  4. Navigation & Polish (Phase 4 & 5)
