# AuthCrunch Role Contract Tasks

## Setup

- [x] T000 Confirm the active worktree is `feat/authcrunch-role-contract`, review
  `design.md`, and verify the feature scope matches the planned AuthCrunch role
  contract.

## Inventory And Contract Design

- [x] T001 Inventory AuthCrunch and Caddy authorization inputs in
  `deploy/compose/caddy/Caddyfile`, `.env.example`, deployment docs, and runtime
  contract scripts.
- [x] T002 Inventory Phoenix browser request/session handling, including
  `DevicePermissions`, `Permissions`, LiveViews, terminal channel authorization,
  and report/device permission consumers.
- [x] T003 Determine the actual AuthCrunch forwarded claim/header names available
  from `inject headers with claims`, using external AuthCrunch/Caddy docs if repo
  evidence is insufficient, and choose the canonical Phoenix inputs.
- [x] T004 Define operator roles and capability mapping for dashboard, devices,
  remote access, alerts, reports, settings, and E2E surfaces.
- [x] T005 Define fail-closed behavior for missing, malformed, or insufficient
  claims without weakening local development workflows.

## Server Implementation

- [x] T006 Implement a small claim parsing and normalization boundary for trusted
  Caddy/AuthCrunch browser requests.
- [x] T007 Map Caddy-normalized roles to existing device and report permission
  maps, reusing `NixstasisWeb.Permissions` where practical.
- [x] T008 Apply role-aware behavior to the first supported set of LiveView
  surfaces without changing device API token, E2E enablement, or terminal session
  token contracts.
- [x] T009 Ensure unauthorized or malformed claim scenarios deny privileged UI
  behavior and avoid logging secrets or full sensitive claim blobs.
- [x] T010 Preserve Caddy `authorize with entra_policy` as the production browser
  authorization edge and do not replace it with Phoenix-only checks.

## Documentation

- [x] T011 Document the final AuthCrunch/Phoenix claim and role contract in
  affected architecture/reference docs.
- [x] T012 Update Caddy/deployment/operations docs for `AUTHORIZED_ROLES`,
  `AUTHORIZED_GROUPS`, JWT key expectations, and operator configuration guidance.
- [x] T013 Update `docs/src/planned-features.md` with final feature status and
  final group-to-role mapping behavior.

## Tests And Verification

- [x] T014 Add unit tests for claim parsing, normalization, and role-to-capability
  mapping.
- [x] T015 Add request or LiveView tests for allowed and denied role scenarios on
  implemented browser surfaces.
- [x] T016 Add tests proving missing or malformed production AuthCrunch claims fail
  closed without granting privileged permissions.
- [x] T017 Verify device runtime API authentication remains unchanged.
- [x] T018 Run `deploy/compose/scripts/check_runtime_contract.sh` if Compose or
  Caddy authorization contract inputs change.
- [x] T019 Run or document applicability of
  `deploy/compose/scripts/validate_stack.sh deploy/compose/.env.example` if
  Compose validation changes.
- [x] T020 Run `mix precommit` from `packages/server` after server changes.
- [x] T021 Run `mdbook build docs` after docs changes.
- [x] T022 Run `hk check -a` before close-out.
- [x] T023 Search docs and server code for stale AuthCrunch, role, group,
  `device_permissions`, and `report_permissions` references.
- [x] T024 Run second-agent implementation review and address actionable quality,
  security, and maintainability findings.

## Completion

- [x] T999 Confirm implementation, docs, tests, and deployment guidance agree.
