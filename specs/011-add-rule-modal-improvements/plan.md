# Implementation Plan: Add Rule Modal Improvements

**Branch**: `011-add-rule-modal-improvements` | **Date**: 2026-02-16 | **Spec**: `specs/011-add-rule-modal-improvements/spec.md`
**Input**: Feature specification from `/specs/011-add-rule-modal-improvements/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command.
See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Upgrade the Add Rule modal in Alerts to match Create Report modal interaction quality and consistency. The implementation will align modal structure, keyboard flow, focus behavior, edit-mode immutability, validation/recovery messaging, and unsaved-change cancellation behavior while keeping existing rule semantics and schema-driven field selection intact.

## Technical Context

**Language/Version**: Elixir 1.19.5, Erlang/OTP 28
**Primary Dependencies**: Phoenix 1.8 LiveView, Ash/AshPhoenix forms, DaisyUI/Tailwind component patterns
**Storage**: Existing Postgres `alert_rules` via Ash resource (no schema changes planned)
**Testing**: ExUnit + Phoenix LiveView tests in `packages/server/test/nixstasis_web/live/alerts_live_test.exs` with focused behavior assertions
**Target Platform**: Phoenix web app (`packages/server`) in modern desktop/laptop browsers
**Project Type**: Monorepo web application
**Performance Goals**: Modal open-to-first-action and input-to-validation feedback remain subjectively instant for normal usage; no measurable regression versus current Add Rule behavior
**Constraints**: Only rule name immutable in edit mode; `Ctrl/Cmd+Enter` save shortcut; plain Enter in text-entry contexts must not force full submit; cancel/Escape confirmation only when dirty; WCAG 2.1 AA modal/form interaction expectations
**Scale/Scope**: Alerts Add Rule modal flow and associated LiveView state/events, plus test coverage updates

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Quality & Simplicity: Pass. Scope constrained to existing alerts LiveView/modal behavior without introducing new persistence layers.
- Behavior-Driven API Testing: Pass. LiveView acceptance tests will use Given/When/Then style behavior validation.
- Targeted Unit Testing: Pass. Logic complexity is expected to stay in LiveView interaction code; no new complex domain algorithm anticipated.
- User Experience First: Pass. This feature is UX-focused and improves interaction consistency and error recovery.
- Branding: Pass. Existing app modal and form styles/patterns are reused.
- Performance Compliance: Pass. No additional expensive operations introduced; schema selection and validation remain bounded.

**Post-Design Check (after Phase 1)**: Pass. Planned artifacts preserve UX-first behavior, testing obligations, and existing architecture simplicity.

## Project Structure

### Documentation (this feature)

```text
specs/011-add-rule-modal-improvements/
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
    ├── assets/
    │   └── js/
    │       └── app.js
    ├── lib/
    │   ├── nixstasis/
    │   │   ├── monitoring/
    │   │   │   └── alert_rule.ex
    │   │   └── schema_options.ex
    │   └── nixstasis_web/
    │       ├── components/
    │       │   └── core_components.ex
    │       └── live/
    │           └── alerts/
    │               ├── index_live.ex
    │               └── rules_live.ex
    └── test/
        └── nixstasis_web/
            └── live/
                └── alerts_live_test.exs
```

**Structure Decision**: Implement modal parity and interaction behavior directly in `AlertLive.Index` (existing Add Rule modal entrypoint), with optional keyboard hook alignment in `assets/js/app.js` only if required to match established modal keyboard patterns.

## Phase 0: Research Output

Research completed in `specs/011-add-rule-modal-improvements/research.md`.
All clarification-derived unknowns are resolved and translated into concrete interaction decisions.

## Phase 1: Design Output

- Data model artifact: `specs/011-add-rule-modal-improvements/data-model.md`
- Contract artifact: `specs/011-add-rule-modal-improvements/contracts/add-rule-modal.openapi.yaml`
- Validation runbook: `specs/011-add-rule-modal-improvements/quickstart.md`

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| None | N/A | N/A |

## Implementation Notes (2026-02-17)

- Add Rule modal now supports create and edit flows in `AlertLive.Index`.
- Modal close path now confirms discard only when draft state is dirty.
- Keyboard behavior aligned with requirements: `Ctrl/Cmd+Enter` save and plain Enter suppression in text-entry inputs.
- Rule management table added to Alerts page with edit and delete actions.
- LiveView tests expanded in `alerts_live_test.exs` to cover create, edit, delete, validation, and cancel-confirm behavior.
- TODO: Brainstorm lifecycle handling for rules whose schema field/version is no longer valid (lock-and-warn, guided remap, auto-disable, or archival workflow) before broad rollout.
