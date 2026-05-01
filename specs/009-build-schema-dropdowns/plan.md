# Implementation Plan: Schema-Driven Builder Dropdowns

**Branch**: `009-build-schema-dropdowns` | **Date**: 2026-02-14 | **Spec**: `specs/009-build-schema-dropdowns/spec.md`
**Input**: Feature specification from `/specs/009-build-schema-dropdowns/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command.
See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement schema-driven dropdown menus in both alert and report builders so users select only valid schema fields
instead of typing free-form paths. The plan introduces a shared schema option service, builder-specific schema-version
state handling, automatic clearing of invalid selections on schema change, and explicit permission-loss behavior that
blocks save. Targets include <=2s option-load latency and measurable reduction of invalid saved configurations.

## Technical Context

**Language/Version**: Elixir 1.19.5, Erlang/OTP 28
**Primary Dependencies**: Phoenix LiveView 1.8+, Ash Framework/AshPhoenix, Ecto
**Storage**: Postgres (existing device schema and reporting data), in-memory LiveView assigns for builder state
**Testing**: ExUnit + Phoenix LiveView tests (BDD-style scenario coverage), targeted unit tests for schema option mapping/validation
**Target Platform**: Phoenix web server (Linux/macOS dev), browser-based LiveView UI
**Project Type**: Monorepo web application (`packages/server`)
**Performance Goals**: 95% of schema selection events populate dropdown options within 2 seconds
**Constraints**: Alert/report builders keep independent schema-version state; fail closed on permission loss; no invalid schema fields can be saved
**Scale/Scope**: Alert and report builder flows in current LiveViews, with schema option lists sized to common product schemas (hundreds of fields)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Quality & Simplicity: Pass. Add one shared schema-options service and reuse in both builders to avoid duplicated logic.
- Behavior-Driven API Testing: Pass. LiveView and context tests will use Given/When/Then style for schema loading, invalidation, and save blocking.
- Targeted Unit Testing: Pass. Schema parsing/normalization and invalid-selection clearing logic will have isolated unit tests.
- User Experience First: Pass. Replace free-text path entry with guided dropdowns and clear inline feedback states.
- Branding: Pass. UI work remains inside existing DaisyUI/Tailwind component patterns and labels.
- Performance Compliance: Pass. Explicit <=2s option-load target captured in spec and verification steps.

**Post-Design Check (after Phase 1)**: Pass. Design artifacts preserve simplicity, include required testing strategy, and encode UX/performance constraints.

## Project Structure

### Documentation (this feature)

```text
specs/009-build-schema-dropdowns/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
packages/
└── server/
    ├── lib/
    │   ├── nixstasis/
    │   │   ├── monitoring/
    │   │   ├── reporting/
    │   │   └── devices/
    │   └── nixstasis_web/
    │       ├── live/
    │       │   ├── alerts/
    │       │   └── reports/
    │       └── controllers/
    ├── test/
    │   ├── nixstasis/
    │   └── nixstasis_web/
    └── priv/
        └── repo/
```

**Structure Decision**: Keep implementation inside existing Phoenix server modules. Add a shared schema-option provider
under `packages/server/lib/nixstasis/` and wire both `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
and `packages/server/lib/nixstasis_web/live/reports/form_component.ex` to consume it. Keep tests in existing
`packages/server/test/nixstasis` and `packages/server/test/nixstasis_web` trees.

## Baseline Metrics Queries

- Invalid-save attempt rate: count telemetry events named `[:nixstasis, :builder, :invalid_save_attempt]` grouped by builder per release window.
- First-attempt completion rate: ratio of `[:nixstasis, :builder, :first_attempt_success]` events to total report/alert save attempts per release window.
- Support ticket volume: count support issues tagged `missing/invalid builder field options` per release window.

## Implementation Notes

- 2026-02-15: Implemented schema-options service, validation API endpoints, and LiveView schema selectors for alerts/reports.
- 2026-02-15: Added telemetry hooks for invalid-save attempts and first-attempt success counters.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| None | N/A | N/A |
