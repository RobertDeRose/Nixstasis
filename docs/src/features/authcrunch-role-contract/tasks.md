# AuthCrunch Role Contract Tasks

## Setup

- [ ] T000 Confirm the active worktree is `feat/authcrunch-role-contract`, review
  `design.md`, and verify the feature scope matches the planned AuthCrunch role
  contract.

## Inventory And Contract Design

- [ ] T001 Inventory AuthCrunch and Caddy authorization inputs in
  `deploy/compose/caddy/Caddyfile`, `.env.example`, deployment docs, and runtime
  contract scripts.
- [ ] T002 Inventory Phoenix browser request/session handling, including
  `DevicePermissions`, `Permissions`, LiveViews, terminal channel authorization,
  and report/device permission consumers.
- [ ] T003 Determine the actual AuthCrunch forwarded claim/header names available
  from `inject headers with claims`, using external AuthCrunch/Caddy docs if repo
  evidence is insufficient, and choose the canonical Phoenix inputs.
- [ ] T004 Define operator roles and capability mapping for dashboard, devices,
  remote access, alerts, reports, settings, and E2E surfaces.
- [ ] T005 Define fail-closed behavior for missing, malformed, or insufficient
  claims without weakening local development workflows.

## Server Implementation

- [ ] T006 Implement a small claim parsing and normalization boundary for trusted
  Caddy/AuthCrunch browser requests.
- [ ] T007 Map normalized roles or groups to existing device and report permission
  maps, reusing `NixstasisWeb.Permissions` where practical.
- [ ] T008 Apply role-aware behavior to the first supported set of LiveView
  surfaces without changing device API token, E2E enablement, or terminal session
  token contracts.
- [ ] T009 Ensure unauthorized or malformed claim scenarios deny privileged UI
  behavior and avoid logging secrets or full sensitive claim blobs.
- [ ] T010 Preserve Caddy `authorize with entra_policy` as the production browser
  authorization edge and do not replace it with Phoenix-only checks.

## Documentation

- [ ] T011 Document the final AuthCrunch/Phoenix claim and role contract in
  affected architecture/reference docs.
- [ ] T012 Update Caddy/deployment/operations docs for `AUTHORIZED_ROLES`,
  `AUTHORIZED_GROUPS`, JWT key expectations, and operator configuration guidance.
- [ ] T013 Update `docs/src/planned-features.md` with final feature status and any
  intentionally deferred role or group mapping work.

## Tests And Verification

- [ ] T014 Add unit tests for claim parsing, normalization, and role-to-capability
  mapping.
- [ ] T015 Add request or LiveView tests for allowed and denied role scenarios on
  implemented browser surfaces.
- [ ] T016 Add tests proving missing or malformed production AuthCrunch claims fail
  closed without granting privileged permissions.
- [ ] T017 Verify device runtime API authentication remains unchanged.
- [ ] T018 Run `deploy/compose/scripts/check_runtime_contract.sh` if Compose or
  Caddy authorization contract inputs change.
- [ ] T019 Run or document applicability of
  `deploy/compose/scripts/validate_stack.sh deploy/compose/.env.example` if
  Compose validation changes.
- [ ] T020 Run `mix precommit` from `packages/server` after server changes.
- [ ] T021 Run `mdbook build docs` after docs changes.
- [ ] T022 Run `hk check -a` before close-out.
- [ ] T023 Search docs and server code for stale AuthCrunch, role, group,
  `device_permissions`, and `report_permissions` references.

## Completion

- [ ] T999 Confirm implementation, docs, tests, and deployment guidance agree;
  summarize any intentionally deferred authorization surfaces or group mapping
  behavior.
