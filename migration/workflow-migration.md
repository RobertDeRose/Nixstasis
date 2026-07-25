<!-- rumdl-disable MD013 -->

# Legacy Workflow Migration Report

Generated: `2026-07-25T03:44:59+00:00`

## Inventory

- Features: 23
- Legacy task files: 21
- Parsed task files: 21
- Unparsed task files: 0
- Parsed legacy tasks: 699
- Reconciliation findings: 16
- `completed`: 16
- `in_progress`: 5
- `planned`: 2

## hk Reconciliation

- Baseline status: `evaluable`
- Current status: `evaluable`
- Recorded dispositions: 0
- Blocking inventory issues: 0

## Artifact Lifecycle

- Temporary candidates present: False
- Conditional backup present: False
- Backup disposition: `not_applicable`
- Backup disposition reason: —

## Checkpoint Evidence

- `pre-commit` `exception` — `HK_SKIP_STEPS=docs git commit -m "chore: adopt dstack workflow"` — The approved migration checkpoint retains legacy task files and incomplete legacy designs until Beads import and semantic reconciliation.
- `pre-commit` `exception` — `HK_SKIP_STEPS=docs git commit -m "chore: record workflow migration plan"` — The Gate 3 checkpoint intentionally retains legacy task files and incomplete designs for Beads import and reconciliation.

## Feature Mapping

- **Feature:** `compose-dev-harness`
  - Target: `compose-dev-harness`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `self-extracting-installer`
  - Target: `self-extracting-installer`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `server-provided-frps-token`
  - Target: `server-provided-frps-token`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `in-memory-ssh-authorized-keys`
  - Target: `in-memory-ssh-authorized-keys`
  - Classification: `in_progress (override)`
  - Roadmap: in-progress
  - Design: —
  - Index: no
  - Findings: 0
- **Feature:** `ash-api-contract-unification`
  - Target: `ash-api-contract-unification`
  - Classification: `in_progress`
  - Roadmap: in-progress
  - Design: —
  - Index: no
  - Findings: 0
- **Feature:** `authcrunch-role-contract`
  - Target: `authcrunch-role-contract`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `production-operations-runbooks`
  - Target: `production-operations-runbooks`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `rich-api-examples`
  - Target: `rich-api-examples`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `server-stary-script-workbench`
  - Target: `server-stary-script-workbench`
  - Classification: `in_progress`
  - Roadmap: in-progress
  - Design: —
  - Index: no
  - Findings: 0
- **Feature:** `server-command-allowlist-management`
  - Target: `server-command-allowlist-management`
  - Classification: `completed (override)`
  - Roadmap: implemented
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `dashboard-device-groups`
  - Target: `dashboard-device-groups`
  - Classification: `planned`
  - Roadmap: planned
  - Design: —
  - Index: no
  - Findings: 0
- **Feature:** `server-curated-command-package-catalog`
  - Target: `server-curated-command-package-catalog`
  - Classification: `planned`
  - Roadmap: planned
  - Design: —
  - Index: no
  - Findings: 0
- **Feature:** `add-rule-modal-improvements`
  - Target: `add-rule-modal-improvements`
  - Classification: `in_progress`
  - Roadmap: in-progress
  - Design: —
  - Index: no
  - Findings: 0
- **Feature:** `dashboard-home`
  - Target: `dashboard-home`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `device-detail-page`
  - Target: `device-detail-page`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `go-client-rewrite`
  - Target: `go-client-rewrite`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `iot-device-monitoring`
  - Target: `iot-device-monitoring`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `packaging-deployment-migration`
  - Target: `packaging-deployment-migration`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `phoenix-ui-polish`
  - Target: `phoenix-ui-polish`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `report-view-improvements`
  - Target: `report-view-improvements`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `schema-driven-builder-dropdowns`
  - Target: `schema-driven-builder-dropdowns`
  - Classification: `in_progress`
  - Roadmap: in-progress
  - Design: —
  - Index: no
  - Findings: 0
- **Feature:** `server-client-e2e-tests`
  - Target: `server-client-e2e-tests`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1
- **Feature:** `starlark-script-system`
  - Target: `starlark-script-system`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: no
  - Findings: 1

## Reconciliation Findings

### Compose dev harness (`compose-dev-harness`)

- `finding:5b9be2888efc` — Roadmap says completed/implemented but completion evidence is missing: implemented-feature index.md
- Classification override: `completed` — Roadmap completion, 21 closed tasks, deploy/compose, and current development docs corroborate delivery.

### Self extracting installer (`self-extracting-installer`)

- `finding:5b9be2888efc` — Roadmap says completed/implemented but completion evidence is missing: implemented-feature index.md
- Classification override: `completed` — Roadmap completion, 13 closed tasks, installer build assets, and release verification corroborate delivery.

### Server provided frps token (`server-provided-frps-token`)

- `finding:5b9be2888efc` — Roadmap says completed/implemented but completion evidence is missing: implemented-feature index.md
- Classification override: `completed` — Roadmap completion, 23 closed tasks, client/server token handling, tests, and contract docs corroborate delivery.

### In memory ssh authorized keys (`in-memory-ssh-authorized-keys`)

- Classification override: `in_progress` — Six validation and close-out tasks remain open, so roadmap completion is not yet supported despite delivered code.

### Authcrunch role contract (`authcrunch-role-contract`)

- `finding:5b9be2888efc` — Roadmap says completed/implemented but completion evidence is missing: implemented-feature index.md
- Classification override: `completed` — Roadmap completion, 26 closed tasks, Caddy role mapping, Phoenix permissions, tests, and docs corroborate delivery.

### Production operations runbooks (`production-operations-runbooks`)

- `finding:5b9be2888efc` — Roadmap says completed/implemented but completion evidence is missing: implemented-feature index.md
- Classification override: `completed` — Roadmap completion, 13 closed tasks, and the current operations runbook set corroborate delivery.

### Rich API examples (`rich-api-examples`)

- `finding:5b9be2888efc` — Roadmap says completed/implemented but completion evidence is missing: implemented-feature index.md
- Classification override: `completed` — Roadmap completion, 15 closed tasks, API examples, OpenAPI references, and tests corroborate delivery.

### Server command allowlist management (`server-command-allowlist-management`)

- `finding:5b9be2888efc` — Roadmap says completed/implemented but completion evidence is missing: implemented-feature index.md
- Classification override: `completed` — Roadmap implementation status, 29 closed tasks, server/client policy code, tests, and docs corroborate delivery.

### Dashboard home (`dashboard-home`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 29 tasks are closed and current dashboard LiveView code, tests, and reader documentation corroborate delivery.

### Device detail page (`device-detail-page`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 38 tasks are closed and current device detail LiveView code, tests, and reader documentation corroborate delivery.

### Go client rewrite (`go-client-rewrite`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 10 final-state tasks are closed and the current Go client, tests, packaging, and reader docs corroborate delivery.

### Iot device monitoring (`iot-device-monitoring`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 53 tasks are closed and current registration, telemetry, monitoring code, tests, and docs corroborate delivery.

### Packaging deployment migration (`packaging-deployment-migration`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 49 tasks are closed and current Compose deployment, release assets, checks, and docs corroborate delivery.

### Phoenix UI polish (`phoenix-ui-polish`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 19 tasks are closed and current LiveView components, UI tests, and reader docs corroborate delivery.

### Report view improvements (`report-view-improvements`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 42 tasks are closed and current reporting LiveViews, tests, and reader docs corroborate delivery.

### Server client e2e tests (`server-client-e2e-tests`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 39 tasks are closed and the current E2E APIs, client harness, tests, and reader docs corroborate delivery.

### Starlark script system (`starlark-script-system`)

- `finding:54e5cd13e8ca` — Roadmap says completed/implemented but completion evidence is missing: T999 closed, implemented-feature index.md
- Classification override: `completed` — All 46 tasks are closed and the current Starlark runtime, CLI, tests, and reader docs corroborate delivery.

## Migration Stages

1. Review this report and confirm the feature slug mapping.
2. Use `classify` and `resolve-findings` to record evidence-backed decisions before import.
3. Run `prepare --apply` to rename feature paths and rewrite links.
4. Run `import-beads --apply` to create Beads state.
5. Use `/migrate-workflow` to reconcile designs, delivered records, and status conflicts.
6. Run `finalize --apply` only after no page includes or links to `tasks.md`.
7. Run `verify --beads` and the normal project checks.
