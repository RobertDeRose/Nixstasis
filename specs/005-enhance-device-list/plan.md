# Implementation Plan: Enhance Device List View

**Branch**: `005-enhance-device-list` | **Date**: 2026-02-04 | **Spec**: [specs/005-enhance-device-list/spec.md](../spec.md)
**Input**: Feature specification from `/specs/005-enhance-device-list/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command.
See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance the device management experience by implementing a sortable, filterable LiveView table (with new IPv4/Account fields), bulk approval actions, and a comprehensive detail modal featuring real-time PCP metric charts and an in-browser SSH terminal via Phoenix Channels.

## Technical Context

**Language/Version**: Elixir 1.19.5 with Erlang/OTP 28
**Primary Dependencies**: Phoenix 1.8+, DaisyUI 5, Tailwind CSS v4, LiveView Streams, Phoenix Channels, Erlang :ssh (via wrapper), ApexCharts (JS Hook)
**Storage**: Postgres (JSONB/GINs supported)
**Testing**: ExUnit (Unit & Integration), Wallaby/Playwright (End-to-End/BDD)
**Target Platform**: Web (Phoenix LiveView)
**Project Type**: Web application
**Performance Goals**: < 5s list filtering, < 10s metric stream latency
**Constraints**: Must use `frps` proxy for device connections

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **I. Quality & Simplicity**: Modular design with dedicated `Nixstasis.Devices` context.
- [x] **II. Behavior-Driven API Testing**: Will implement tests for PCP data ingestion and terminal socket behavior.
- [x] **III. Targeted Unit Testing**: Parsing logic for PCP data and SSH connection state machines will be unit tested.
- [x] **IV. User Experience First**: Prioritizing responsive table (LiveView Streams) and rich visualizations (Charts, Terminal).
- [x] **V. Branding**: UI will strictly follow DaisyUI 5 and Tailwind v4 guidelines.
- [x] **VI. Performance Compliance**: LiveView Streams chosen specifically for list performance; defined latency targets in Spec.

## Project Structure

### Documentation (this feature)

```text
specs/005-enhance-device-list/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
lib/
├── nixstasis/
│   ├── devices/                 # [NEW] Dedicated context
│   │   ├── device.ex            # [NEW] Schema
│   │   ├── ssh_client.ex        # [NEW] SSH connection logic
│   │   └── pcp_client.ex        # [NEW] PCP API integration
│   └── devices.ex               # [NEW] Context API
├── nixstasis_web/
│   ├── live/
│   │   ├── device_live/         # [NEW] LiveView directory
│   │   │   ├── index.ex         # [NEW] List view (table, bulk actions)
│   │   │   ├── show.ex          # [NEW] Modal (metrics, terminal)
│   │   │   └── index.html.heex  # [NEW] Template
│   └── channels/
│       └── terminal_channel.ex  # [NEW] Channel for xterm.js <-> SSH pipe
assets/
└── js/
    └── terminal.js              # [NEW] xterm.js integration hook
```

**Structure Decision**: Standard Phoenix Context + LiveView structure. Introducing a dedicated `Nixstasis.Devices` context to encapsulate the new domain logic, separate from existing `Inventory` or `Core` contexts if they exist, to maintain modularity.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| N/A | | |
