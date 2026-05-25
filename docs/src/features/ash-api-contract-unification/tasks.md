# Ash API Contract Unification Tasks

## Setup

- [x] T000 Confirm the active worktree is `feat/ash-api-contract-unification` and
  the feature spec matches the intended non-UI Ash/OpenAPI unification scope.

## Inventory And Classification

- [x] T001 Inventory every non-UI route in
  `packages/server/lib/nixstasis_web/router.ex`, including `/api/v1`, `/api/json`,
  `/e2e`, `/_nixstasis/laptop`, builder endpoints, and generated/static OpenAPI
  paths.
- [x] T002 Map each inventoried endpoint to its controller or Ash resource/action,
  its tests, and its current docs/reference location.
- [x] T003 Add a committed endpoint inventory table under
  `docs/src/features/ash-api-contract-unification/` with route, current handler,
  consumer, docs/source OpenAPI file, classification, migration decision, and
  rationale.
- [x] T004 Classify each endpoint as `ash-backed`, `retained-controller`,
  `ui-only`, or `deferred` using the rules in `design.md`.
- [x] T005 Identify compatibility-sensitive consumers for each non-UI endpoint,
  including the Go client, Caddy, E2E harness, builder tooling, dev-laptop
  diagnostics, and external automation.
- [x] T006 Reconcile the inventory against `device-api.yaml`, `builder-api.yaml`,
  `report-api.yaml`, `e2e-api.yaml`, `openapi/index.md`, and `contracts.md`.

## Contract Design

- [x] T007 Define the Ash resource/action model for each endpoint classified as
  `ash-backed`.
- [x] T008 Define request and response schemas for converted endpoints so generated
  OpenAPI matches the maintained runtime contract.
- [x] T009 Document explicit rationale for every `retained-controller` endpoint.
- [x] T010 Treat Caddy `GET /api/v1/check_domain` as retained-controller by
  default unless the inventory proves an Ash action preserves the deployment
  boundary more clearly.
- [x] T011 Treat `/e2e` endpoints as retained-controller by default unless the
  inventory proves a specific endpoint can move to Ash without weakening protocol,
  locking, seed, log, or typed-error behavior.
- [x] T012 Treat `/_nixstasis/laptop/*` diagnostics as retained-controller or
  deferred by default unless the inventory proves they are durable non-UI product
  contracts.
- [x] T013 Consult Ash, Ash JSON:API, and Ash Phoenix usage rules before designing
  generated route/schema changes.

## Server Implementation

- [x] T014 Convert the first approved group of resource/action-oriented non-UI
  endpoints to Ash-backed resources/actions or Ash JSON routes.
- [x] T015 Preserve existing authentication and authorization semantics for
  converted endpoints.
- [x] T016 Preserve existing response shapes, status codes, validation errors, and
  error payload classes unless a versioned migration is explicitly documented.
- [x] T017 Update or remove now-redundant Phoenix controller code only after the
  Ash-backed contract is tested.
- [x] T018 Refresh generated OpenAPI after Ash resource/action changes.
- [x] T019 Run named Ash codegen for committed resource changes and avoid committing
  `*_dev` migration or snapshot files.

## Tests

- [x] T020 Add or update server tests for each converted endpoint's success path.
- [x] T021 Add or update server tests for validation errors, authorization failures,
  and important edge cases for each converted endpoint.
- [x] T022 Run Go client transport tests against registration, heartbeat, command
  polling, command result, and deferred payload contracts if those endpoints move;
  not required for the builder-only implementation slice because Go-client device
  endpoints remain deferred.
- [x] T023 Run E2E harness tests if `/e2e` endpoints move or receive Ash wrappers;
  not required for the builder-only implementation slice because `/e2e` endpoints
  remain retained-controller.
- [x] T024 Add OpenAPI generation or schema checks proving converted endpoints are
  present in generated OpenAPI.

## Documentation

- [x] T025 Update `docs/src/client-server-interface.md` so non-UI API contracts
  point to generated OpenAPI where applicable.
- [x] T026 Update `docs/src/reference/openapi/` to remove duplicate hand-maintained
  sections only when generated OpenAPI fully covers the converted contract.
- [x] T027 Add retained-controller rationale to reference docs for endpoints that
  intentionally remain outside Ash.
- [x] T028 Update affected module pages, such as server web, server devices,
  server E2E, server reporting, deployment compose, or runtime boundaries.
- [x] T029 Update `docs/src/planned-features.md` to reflect the final status and any
  intentionally deferred API groups.

## Verification

- [x] T030 Run `mix ash.codegen --check` from `packages/server` if Ash resources
  changed.
- [x] T031 Run `mix precommit` from `packages/server` after server changes.
- [x] T032 Run affected Go client tests if any Go-client API contract moved.
- [x] T033 Run `mdbook build docs` after docs/reference updates.
- [x] T034 Diff generated OpenAPI before and after conversion and confirm every
  converted endpoint appears with the intended schema.
- [x] T035 Search docs and code for stale references to converted hand-maintained
  OpenAPI sections or controller-only contract descriptions.
- [x] T036 Verify each retained bespoke OpenAPI section has route-specific
  retained-controller rationale.

## Completion

- [x] T999 Confirm implementation, generated OpenAPI, retained-controller rationale,
  docs, and tests agree; summarize any deferred non-UI endpoints and why they were
  not converted in this feature.
