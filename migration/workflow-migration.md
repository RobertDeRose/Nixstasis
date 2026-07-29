<!-- rumdl-disable MD013 -->

# Legacy Workflow Migration Report

Generated: `2026-07-29T12:59:43+00:00`

## Inventory

- Features: 23
- Legacy task files: 21
- Parsed task files: 21
- Unparsed task files: 0
- Parsed legacy tasks: 699
- Reconciliation findings: 0
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
- `pre-commit` `exception` — `HK_SKIP_STEPS=docs git commit -m "chore: normalize legacy feature paths"` — The Gate 4 checkpoint intentionally retains legacy task files and incomplete designs for Beads import and reconciliation.

## Feature Mapping

- **Feature:** `compose-dev-harness`
  - Target: `compose-dev-harness`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
- **Feature:** `self-extracting-installer`
  - Target: `self-extracting-installer`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
- **Feature:** `server-provided-frps-token`
  - Target: `server-provided-frps-token`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
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
  - Index: yes
  - Findings: 0
- **Feature:** `production-operations-runbooks`
  - Target: `production-operations-runbooks`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
- **Feature:** `rich-api-examples`
  - Target: `rich-api-examples`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
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
  - Index: yes
  - Findings: 0
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
  - Index: yes
  - Findings: 0
- **Feature:** `device-detail-page`
  - Target: `device-detail-page`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
- **Feature:** `go-client-rewrite`
  - Target: `go-client-rewrite`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
- **Feature:** `iot-device-monitoring`
  - Target: `iot-device-monitoring`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
- **Feature:** `packaging-deployment-migration`
  - Target: `packaging-deployment-migration`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
- **Feature:** `phoenix-ui-polish`
  - Target: `phoenix-ui-polish`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
- **Feature:** `report-view-improvements`
  - Target: `report-view-improvements`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0
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
  - Index: yes
  - Findings: 0
- **Feature:** `starlark-script-system`
  - Target: `starlark-script-system`
  - Classification: `completed (override)`
  - Roadmap: completed
  - Design: —
  - Index: yes
  - Findings: 0

## Reconciliation Findings

### Compose dev harness (`compose-dev-harness`)

- Classification override: `completed` — Roadmap completion, 21 closed tasks, deploy/compose, and current development docs corroborate delivery.

### Self extracting installer (`self-extracting-installer`)

- Classification override: `completed` — Roadmap completion, 13 closed tasks, installer build assets, and release verification corroborate delivery.

### Server provided frps token (`server-provided-frps-token`)

- Classification override: `completed` — Roadmap completion, 23 closed tasks, client/server token handling, tests, and contract docs corroborate delivery.

### In memory ssh authorized keys (`in-memory-ssh-authorized-keys`)

- Classification override: `in_progress` — Six validation and close-out tasks remain open, so roadmap completion is not yet supported despite delivered code.

### Authcrunch role contract (`authcrunch-role-contract`)

- Classification override: `completed` — Roadmap completion, 26 closed tasks, Caddy role mapping, Phoenix permissions, tests, and docs corroborate delivery.

### Production operations runbooks (`production-operations-runbooks`)

- Classification override: `completed` — Roadmap completion, 13 closed tasks, and the current operations runbook set corroborate delivery.

### Rich API examples (`rich-api-examples`)

- Classification override: `completed` — Roadmap completion, 15 closed tasks, API examples, OpenAPI references, and tests corroborate delivery.

### Server command allowlist management (`server-command-allowlist-management`)

- Classification override: `completed` — Roadmap implementation status, 29 closed tasks, server/client policy code, tests, and docs corroborate delivery.

### Dashboard home (`dashboard-home`)

- Classification override: `completed` — All 29 tasks are closed and current dashboard LiveView code, tests, and reader documentation corroborate delivery.

### Device detail page (`device-detail-page`)

- Classification override: `completed` — All 38 tasks are closed and current device detail LiveView code, tests, and reader documentation corroborate delivery.

### Go client rewrite (`go-client-rewrite`)

- Classification override: `completed` — All 10 final-state tasks are closed and the current Go client, tests, packaging, and reader docs corroborate delivery.

### Iot device monitoring (`iot-device-monitoring`)

- Classification override: `completed` — All 53 tasks are closed and current registration, telemetry, monitoring code, tests, and docs corroborate delivery.

### Packaging deployment migration (`packaging-deployment-migration`)

- Classification override: `completed` — All 49 tasks are closed and current Compose deployment, release assets, checks, and docs corroborate delivery.

### Phoenix UI polish (`phoenix-ui-polish`)

- Classification override: `completed` — All 19 tasks are closed and current LiveView components, UI tests, and reader docs corroborate delivery.

### Report view improvements (`report-view-improvements`)

- Classification override: `completed` — All 42 tasks are closed and current reporting LiveViews, tests, and reader docs corroborate delivery.

### Server client e2e tests (`server-client-e2e-tests`)

- Classification override: `completed` — All 39 tasks are closed and the current E2E APIs, client harness, tests, and reader docs corroborate delivery.

### Starlark script system (`starlark-script-system`)

- Classification override: `completed` — All 46 tasks are closed and the current Starlark runtime, CLI, tests, and reader docs corroborate delivery.

## Resolved Findings

- `dashboard-home` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed dashboard delivery record, closed implementation tasks, current LiveView, tests, and commit evidence establish completion.
- `device-detail-page` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed device detail delivery record, closed tasks, current LiveView, tests, and commit evidence establish completion.
- `go-client-rewrite` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed Go client delivery record, closed final-state tasks, current client, tests, packaging, and commit evidence establish completion.
- `iot-device-monitoring` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed monitoring delivery record, closed tasks, current server behavior, tests, and commit evidence establish completion.
- `packaging-deployment-migration` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed deployment delivery record, closed tasks, current Compose and release evidence, and related commit establish completion.
- `phoenix-ui-polish` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed UI delivery record, closed tasks, current shared components, tests, and commit evidence establish completion.
- `report-view-improvements` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed reporting delivery record, closed tasks, current LiveViews, tests, and commit evidence establish completion.
- `server-client-e2e-tests` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed E2E delivery record, closed tasks, current client/server harness, tests, and commit evidence establish completion.
- `starlark-script-system` `finding:8b0471486c13` — Roadmap says completed/implemented but completion evidence is missing: T999 closed — Reviewed Starlark delivery record, closed tasks, current runtime, tests, and commit evidence establish completion.

## Migration Stages

1. Review this report and confirm the feature slug mapping.
2. Use `classify` and `resolve-findings` to record evidence-backed decisions before import.
3. Run `prepare --apply` to rename feature paths and rewrite links.
4. Run `import-beads --apply` to create Beads state.
5. Use `/migrate-workflow` to reconcile designs, delivered records, and status conflicts.
6. Run `finalize --apply` only after no page includes or links to `tasks.md`.
7. Run `verify --beads` and the normal project checks.
