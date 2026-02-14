# Implementation Plan: Server-Client End-to-End Tests

**Branch**: `008-server-client-e2e-tests` | **Date**: 2026-02-10 | **Spec**: `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/008-server-client-e2e-tests/spec.md`
**Input**: Feature specification from `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/008-server-client-e2e-tests/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command.
See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Deliver a repeatable end-to-end test capability that exercises the Go client against the Phoenix server using synthetic
test data. The solution must support full-suite and targeted journey runs via manual and CI triggers, enforce compatible
client/server pairing (same major version), record run metadata, and provide per-journey logs plus a summary report.
Primary success targets are a full-suite runtime <= 15 minutes and results available within 5 minutes of completion.

## Technical Context

**Language/Version**: Elixir ~> 1.19 (server, OTP 28), Go 1.25.4 (client)
**Primary Dependencies**: Phoenix 1.8+ (LiveView), Ecto/Postgres; Go: cobra/viper, MQTT (paho), websocket (gorilla)
**Storage**: Postgres for server data and run metadata; filesystem artifacts for logs/reports
**Testing**: ExUnit (server), Go test (client), E2E harness with BDD-style assertions
**Target Platform**: Linux server for Phoenix; Linux-based devices for client; local dev on macOS/Linux
**Project Type**: Monorepo with server (web/API) + client (agent)
**Performance Goals**: Full E2E suite <= 15 minutes; results available <= 5 minutes after completion
**Constraints**: Synthetic test data only; same-major-version pairing required; no production data usage
**Scale/Scope**: Initial critical journeys ~5; 1-2 concurrent E2E runs; results retained for release review

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Quality & Simplicity: Pass. Avoid new top-level projects; reuse existing test harness patterns.
- Behavior-Driven API Testing: Pass. E2E scenarios will use Given/When/Then structure and report per-journey outcomes.
- Targeted Unit Testing: Pass. Complex runner helpers and data reset logic will have isolated unit tests.
- User Experience First: Pass. Test reports prioritized for clarity and fast release decisions.
- Branding: Pass. No UI changes; if a report UI is introduced later, follow branding guidelines.
- Performance Compliance: Pass. Runtime and reporting targets captured as success criteria.

**Post-Design Check (after Phase 1)**: Pass. Artifacts align with principles and avoid unnecessary complexity.

## Project Structure

### Documentation (this feature)

```text
specs/008-server-client-e2e-tests/
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
├── server/
│   ├── lib/
│   ├── config/
│   ├── priv/
│   ├── assets/
│   └── test/
├── client/
│   ├── cmd/
│   ├── internal/
│   ├── scripts/
│   └── bin/
├── caddy/
└── frp/
```

**Structure Decision**: Keep E2E harness assets within existing packages to avoid new top-level projects. Server-side
fixtures live under `packages/server/test/support` and `packages/server/test/e2e`, while client-side helpers live under
`packages/client/scripts/e2e` alongside the existing mock API tooling.
