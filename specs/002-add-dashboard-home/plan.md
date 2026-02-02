# Implementation Plan: IoT Dashboard Homepage

**Branch**: `002-add-dashboard-home` | **Date**: 2026-02-01 | **Spec**: [specs/002-add-dashboard-home/spec.md](spec.md)
**Input**: Feature specification from `specs/002-add-dashboard-home/spec.md`

## Summary

Implement a real-time dashboard homepage for IoT Operators using Phoenix LiveView. The dashboard will display vital fleet statistics (Total Devices, Online/Offline, Pending Approvals, Active Alerts) and provide navigation to core management features. Data will be aggregated directly from the database and updated in real-time via Phoenix PubSub.

## Technical Context

**Language/Version**: Elixir 1.19.5 (Phoenix 1.8+)
**Primary Dependencies**: `phoenix_live_view`, `ecto_sql`, `daisyui`
**Storage**: Postgres (Aggregation queries on `devices` and `alerts` tables)
**Testing**: `ex_unit` for Context logic, `Phoenix.LiveViewTest` for dashboard UI.
**Target Platform**: Web (Responsive)
**Project Type**: Phoenix Monolith
**Performance Goals**: Sub-second dashboard load time; real-time updates < 1s latency.
**Constraints**: Single role (all users see all data); Snapshot stats only (no historical data).
**Scale/Scope**: Homepage feature within existing Phoenix application.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles
- [x] **Quality & Simplicity**: Simple aggregation logic; no complex caching or historical data store needed.
- [x] **Behavior-Driven API Testing**: LiveView tests will verify user scenarios (Seeing stats update).
- [x] **Targeted Unit Testing**: Context functions for counting/aggregating will be unit tested.
- [x] **User Experience First**: Real-time updates via LiveView provide immediate feedback.
- [x] **Performance Compliance**: Optimized DB queries for counts.

### Technology Standards
- [x] **Language**: Elixir 1.19.5
- [x] **Frameworks**: Phoenix 1.8+, DaisyUI
- [x] **Database**: Postgres

## Project Structure

### Documentation (this feature)

```text
specs/002-add-dashboard-home/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code

```text
lib/
├── nixstasis/
│   ├── devices.ex       # Existing context (add count functions)
│   └── alerts.ex        # Existing context (add count functions)
├── nixstasis_web/
│   ├── live/
│   │   └── dashboard_live/
│   │       ├── index.ex # Dashboard LiveView
│   │       └── index.html.heex
│   └── components/      # Shared components (stats cards, nav)
test/
├── nixstasis/
│   ├── devices_test.exs
│   └── alerts_test.exs
└── nixstasis_web/
    └── live/
        └── dashboard_live_test.exs
```

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| None | N/A | N/A |
