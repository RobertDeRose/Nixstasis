# Implementation Plan: Devices Page and Device Modal Improvements

**Branch**: `012-improve-devices-modal` | **Date**: 2026-02-20 | **Spec**: `specs/012-improve-devices-modal/spec.md`
**Input**: Feature specification from `/specs/012-improve-devices-modal/spec.md` plus user planning directives for column updates, additive filters, and spec-005 modal reuse.

**Note**: This template is filled in by the `/speckit.plan` command.
See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Update the Devices page to add a Product column, relabel Device Name to MAC Address, introduce additive click-to-filter behavior across Product/Account Number/Status, wire MAC links to the existing spec-005 device modal so PCP data views and xterm SSH are fully accessible from this page, and align/implement the corresponding device list and modal contract endpoints.

## Technical Context

**Language/Version**: Elixir 1.19.5, Erlang/OTP 28
**Primary Dependencies**: Phoenix 1.8 LiveView, Ash resources/context in `Nixstasis.Devices`, Phoenix Channels, xterm.js hook (`assets/js/hooks/terminal.js`), existing PCP integrations from spec 005
**Storage**: Existing Postgres-backed device resources (no new storage engine)
**Testing**: ExUnit + LiveView integration tests (`packages/server/test/nixstasis_web/live/device_live_test.exs`), controller contract tests (`packages/server/test/nixstasis_web/controllers/device_controller_test.exs`), and channel tests for terminal behavior (`packages/server/test/nixstasis_web/channels/terminal_channel_test.exs`)
**Target Platform**: Phoenix web app in desktop and mobile browsers
**Project Type**: Monorepo web application (`packages/server`)
**Performance Goals**: Filter interactions and modal launch remain responsive for normal fleet pages; preserve prior modal readiness expectations from spec 005
**Constraints**: Must reuse existing modal behavior (terminal + PCP), preserve current permission checks, and keep list context intact when modal closes
**Scale/Scope**: Devices page table interactions, modal entrypoint wiring, and contract-consistent API endpoint behavior; no separate modal rewrite

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Quality & Simplicity: Pass. Plan reuses existing device modal and extends current list interactions instead of introducing parallel UX paths.
- Behavior-Driven API Testing: Pass. Behavior-focused tests will cover additive filtering, filter removal semantics, modal launch by MAC link, and device endpoint contract behavior.
- Targeted Unit Testing: Pass. Complex filter-state merge/removal logic will have targeted test coverage.
- User Experience First: Pass. Requested list clarity and modal accessibility improvements are primary user-facing outcomes.
- Branding: Pass. Existing page/modal component styling remains the baseline.
- Performance Compliance: Pass. Filter dimensions are bounded and align with existing table/query behavior.

**Post-Design Check (after Phase 1)**: Pass. Design artifacts keep scope constrained, emphasize UX consistency, and preserve existing performance/test obligations.

## Project Structure

### Documentation (this feature)

```text
specs/012-improve-devices-modal/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── devices-page.openapi.yaml
└── tasks.md
```

### Source Code (repository root)

```text
packages/
└── server/
    ├── assets/
    │   └── js/
    │       └── hooks/
    │           └── terminal.js
    ├── lib/
    │   ├── nixstasis/
    │   │   ├── devices.ex
    │   │   └── devices/
    │   │       ├── device.ex
    │   │       └── ssh_client.ex
    │   └── nixstasis_web/
    │       ├── channels/
    │       │   └── terminal_channel.ex
    │       └── live/
    │           └── device_live/
    │               ├── index.ex
    │               ├── index.html.heex
    │               ├── show.ex
    │               └── show.html.heex
    └── test/
        └── nixstasis_web/
            ├── channels/
            │   └── terminal_channel_test.exs
            └── live/
                └── device_live_test.exs
```

**Structure Decision**: Keep implementation in existing Devices LiveView modules (`device_live/index` + existing modal show flow), extending list columns/filter state and reusing existing modal plumbing already introduced by spec 005.

## Phase 0: Research Output

Research completed in `specs/012-improve-devices-modal/research.md`.
All technical unknowns, including filter removal behavior, were resolved.

## Phase 1: Design Output

- Data model artifact: `specs/012-improve-devices-modal/data-model.md`
- Contract artifact: `specs/012-improve-devices-modal/contracts/devices-page.openapi.yaml`
- Validation runbook: `specs/012-improve-devices-modal/quickstart.md`

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| None | N/A | N/A |
