# Implementation Plan: IoT Device Monitoring

**Branch**: `001-iot-device-monitoring` | **Date**: 2026-01-31 | **Spec**:
[specs/001-iot-device-monitoring/spec.md](spec.md)
**Input**: Feature specification from `/specs/001-iot-device-monitoring/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the
execution workflow.

## Summary

Implement an IoT device monitoring system using Elixir/Phoenix that allows devices to self-register with dynamic data
schemas (stored as JSONB), report heartbeats, and receive commands. The system includes a Dashboard (LiveView + daisyUI)
for device approval, status monitoring, alerts, and custom reporting.

## Technical Context

**Language/Version**: Elixir 1.19.5+ (latest stable), Erlang/OTP 28+ **Primary Dependencies**:

- Phoenix 1.8+
- Phoenix LiveView 1.1+
- Ecto SQL with Postgres
- Jason (JSON library)
- DaisyUI (CSS component library) **Storage**: Postgres 15+ (using JSONB for dynamic schemas) **Testing**: ExUnit
(Unit/Integration), Mox (Mocking) **Target Platform**: Linux server (behind Caddy + FRP) **Project Type**: Web
Application (Phoenix Monolith with LiveView) **Performance Goals**: Real-time dashboard updates (sub-100ms), support for
1000+ concurrent devices **Constraints**:
- Must use existing Caddy/FRP infrastructure
- Dynamic schema fields must be indexable/searchable
- Device approval workflow required for security

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **I. Quality & Simplicity**: Plan uses standard Phoenix patterns and leverages Postgres for complexity (dynamic
  schema).
- [x] **II. Behavior-Driven API Testing**: Plan includes contract/integration tests for API endpoints.
- [x] **III. Targeted Unit Testing**: Plan includes unit tests for Schema parsing and Alert Logic.
- [x] **IV. User Experience First**: Dashboard uses LiveView for real-time responsiveness.
- [x] **V. Performance Compliance**: Efficient JSONB indexing and LiveView updates ensure performance.

## Project Structure

### Documentation (this feature)

```text
specs/001-iot-device-monitoring/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

This is a monorepo with multiple packages that all relate to overarching application.
Inside the `packages` directory are subdirectories for `client`, `caddy`, and `frp` packages.

For this feature, all work will be done inside `packages/overwarch`, which will replace the legacy `server` package.

```text
packages/nixstasis
└── server
    ├── assets                # Web Assets
    │   ├── css
    │   ├── js
    │   └── vendor
    ├── config                # Application Configuration
    ├── lib                   # Elixir Module
    │   ├── nixstasis
    │   │   ├── devices/      # Context for Devices, Schemas, Approvals
    │   │   ├── monitoring/   # Context for Heartbeats, Alerts
    │   │   └── reporting/    # Context for Custom Reports
    │   └── nixstasis_web
    │       ├── live/         # LiveView Dashboard components
    │       │   ├── devices/
    │       │   ├── alerts/
    │       │   └── reports/
    │       ├── components    # DaisyUI components
    │       └── controllers   # API Controllers (Registration, Heartbeat)
    └── test
        ├── nixstasis_web
        │   └── controllers
        └── support
```

**Structure Decision**: Standard Phoenix Context-based structure (Contexts: `Devices`, `Monitoring`, `Reporting`).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
<!-- markdownlint-disable-next-line MD013 -->
| Dynamic Schema (JSONB) | Requirements specify devices define their own data structure | Fixed columns require migrations for every new device type |
<!-- markdownlint-disable-next-line MD013 -->
| FRP/Caddy Integration | Requirement to support remote connectivity behind NAT | Direct port forwarding is less secure and harder to manage |
