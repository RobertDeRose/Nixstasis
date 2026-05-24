# Ash API Contract Unification

## Summary

Move non-UI HTTP API contracts onto Ash-backed resources and actions wherever the
endpoint represents a durable product contract. The goal is for non-UI API models
and endpoints to generate OpenAPI schema from Ash instead of relying on duplicate
hand-maintained controller documentation.

This feature is intentionally scoped to non-UI API surfaces. Browser routes,
LiveView screens, and UI-only workflow handlers remain outside the conversion
scope unless they expose a durable non-UI contract.

## Source Of Intent

This spec is seeded from `docs/src/planned-features.md` entry
`ash-api-contract-unification`, with the additional user constraint that all API
models should use Ash models so all non-UI API endpoints generate OpenAPI schema.

## Goals

- Inventory every non-UI endpoint under `/api/v1`, `/api/json`, `/e2e`,
  `/_nixstasis/laptop`, and any related generated or hand-maintained API
  reference surface.
- Classify each non-UI endpoint as resource/action-oriented, workflow-only, or
  intentionally retained outside Ash.
- Move resource/action-oriented non-UI endpoints to Ash resources, actions, or
  Ash JSON/OpenAPI routes where the behavior maps cleanly.
- Preserve existing wire contracts for the Go client, Caddy domain approval,
  builder APIs, and E2E harness unless a deliberate versioned contract change is
  documented in this feature.
- Make generated OpenAPI the canonical reference for converted non-UI API
  contracts.
- Keep any retained bespoke endpoints documented under `docs/src/reference/` with
  explicit rationale for why they do not generate from Ash.

## Non-Goals

- Converting browser LiveView routes or UI-only interactions into API routes.
- Replacing Ash JSON/OpenAPI generation with a separate OpenAPI generator.
- Changing device runtime authentication, Caddy/AuthCrunch browser
  authentication, terminal authorization, or E2E enablement gates.
- Reworking production ingress, FRP runtime behavior, or deployment topology.
- Forcing workflow-only endpoints into Ash when doing so would obscure behavior
  or make the contract less safe.

## Current Behavior

- Some API contracts are implemented as bespoke Phoenix controllers under
  `/api/v1` and `/e2e`.
- Ash-backed APIs are exposed separately through generated surfaces such as
  `/api/json` and `packages/server/priv/static/openapi.yaml`.
- API reference docs include hand-maintained OpenAPI or prose contract sections
  for endpoints not fully represented by generated Ash OpenAPI.
- This creates drift risk between controller code, Ash resources, generated
  OpenAPI, and documentation.

## Proposed Scope

In scope:

- Non-UI API endpoints consumed by the Go client, Caddy, the E2E harness, builder
  tooling, dev-laptop diagnostics, or external automation.
- Endpoint request and response models for those non-UI APIs.
- OpenAPI generation and reference docs for converted contracts.
- Tests that prove converted endpoints preserve existing response shapes, status
  codes, validation behavior, and authentication behavior.

Out of scope:

- Browser-only LiveView interactions.
- HTML routes and UI controller actions.
- UI-only helper endpoints that are not intended as durable API contracts, unless
  the inventory explicitly reclassifies them as non-UI APIs.

## Endpoint Classification Rules

Classify each endpoint into exactly one bucket before implementation:

- `ash-backed`: resource/action-oriented behavior that should be implemented as
  Ash resources/actions and included in generated OpenAPI.
- `retained-controller`: workflow behavior where a Phoenix controller remains the
  clearest boundary. These endpoints need retained reference docs and rationale.
- `ui-only`: browser or LiveView-only behavior that is out of scope for this
  feature.
- `deferred`: non-UI endpoint that should eventually move to Ash but needs a
  separate migration because of compatibility, auth, or workflow risk.

The initial expectation is that device, command, builder, report, alert-rule, and
E2E product-contract endpoints should be evaluated for Ash backing. Caddy TLS
approval and terminal session workflows may remain controller-owned if the
inventory shows Ash would make those contracts less clear.

Initial review defaults:

- Caddy `GET /api/v1/check_domain` should start as `retained-controller`. It is
  an ingress ask workflow called by Caddy, currently documented as a runtime
  boundary, and has a simple non-resource response contract. Implementation may
  revisit this only if an Ash action can preserve the Caddy-owned behavior without
  obscuring the deployment contract.
- `/e2e` run and result endpoints should start as `retained-controller` unless a
  narrower implementation slice proves an Ash action can preserve enablement
  gates, protocol-version checks, idempotent run reuse, environment locks, seed
  execution, log access, and typed errors. They are non-UI APIs, but many are
  workflow controls rather than simple resources.
- Device registration, heartbeat, command results, command payload fetches,
  builder schema options, builder validation, report result previews, and any
  alert-rule APIs should be evaluated first for Ash-backed models/actions because
  they are durable non-UI product contracts with request/response models.
- `/_nixstasis/laptop/*` diagnostics should start as `retained-controller` or
  `deferred`. They are development-harness diagnostics rather than product API
  contracts and must not be promoted into production API guidance by accident.

## Compatibility Requirements

- Existing Go client registration, heartbeat, command result, deferred payload,
  and command polling behavior must continue to work unless a versioned migration
  is explicitly documented.
- Existing Caddy `GET /api/v1/check_domain` behavior must remain compatible with
  the deployment Caddyfile unless the endpoint is deliberately retained as a
  controller with rationale.
- E2E harness endpoints must keep current enablement gates, lock semantics,
  idempotency behavior, and result submission contracts unless changed by a
  documented versioned migration.
- Builder API validation and schema lookup behavior must preserve existing error
  classes and response shapes.
- Auth and authorization semantics for device API keys, AuthCrunch/Caddy headers,
  E2E gates, and operator-only endpoints must remain explicit and tested.

## Implementation Approach

1. Inventory routes from `packages/server/lib/nixstasis_web/router.ex` and map
   them to controllers, Ash resources, generated OpenAPI paths, and reference
   docs.
2. Create a committed endpoint inventory table under this feature directory before
   converting endpoints. The table must include route, current handler, consumer,
   docs/source OpenAPI file, classification, migration decision, and rationale.
3. Convert the lowest-risk non-UI resource/action endpoints first, preserving
   response payloads and status codes with tests.
4. Generate or refresh OpenAPI from Ash after each converted API group.
5. Remove duplicate hand-maintained OpenAPI sections only when generated OpenAPI
   covers the same contract completely.
6. For retained controllers, document the reason they are outside Ash and keep
   their contract docs under `docs/src/reference/`.
7. Reconcile docs and tests before marking the feature complete.
8. Before designing Ash route changes, consult the in-repo Ash, Ash JSON:API, and
   Ash Phoenix usage rules under `packages/server/deps/*/usage-rules.md` or the
   `mix usage_rules.*` tasks so generated route/schema work follows dependency
   guidance.

## Docs And Pages Likely Affected

- `docs/src/client-server-interface.md`
- `docs/src/reference/openapi/`
- `docs/src/modules/server-web.md`
- `docs/src/modules/server-devices.md`
- `docs/src/modules/server-e2e.md`
- `docs/src/modules/server-reporting.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/planned-features.md`
- `packages/server/priv/static/openapi.yaml`

Existing bespoke OpenAPI files that must be reconciled:

- `docs/src/reference/openapi/device-api.yaml`
- `docs/src/reference/openapi/builder-api.yaml`
- `docs/src/reference/openapi/report-api.yaml`
- `docs/src/reference/openapi/e2e-api.yaml`
- `docs/src/reference/openapi/index.md`
- `docs/src/reference/contracts.md`

## Code Areas Likely Affected

- `packages/server/lib/nixstasis_web/router.ex`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_result_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/builder_schema_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/builder_config_validation_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/tls_controller.ex`
- `packages/server/lib/nixstasis/domain.ex`
- Ash resources and actions under `packages/server/lib/nixstasis/`
- Server controller, domain, and OpenAPI tests under `packages/server/test/`

## Validation

- Route inventory proves every non-UI API endpoint has a classification.
- The committed endpoint inventory reconciles every bespoke OpenAPI file with
  either generated Ash OpenAPI coverage or retained-controller rationale.
- Generated OpenAPI includes each endpoint converted to Ash-backed contracts.
- Tests prove converted endpoints preserve existing request/response shapes,
  status codes, validation errors, and authentication behavior.
- Go client transport tests continue to pass for registration, heartbeat, command
  polling, command results, and deferred payload fetches.
- E2E harness tests continue to pass for converted or retained `/e2e` contracts.
- `mix ash.codegen --check` passes when Ash resources change.
- Ash/Ash JSON:API usage rules are consulted before implementing route/schema
  changes.
- `mix precommit` passes in `packages/server` after server changes.
- `mdbook build docs` passes after reference docs are reconciled.
- A final search confirms retained hand-maintained OpenAPI sections have explicit
  rationale and converted sections are not duplicated.

## Reconciliation Bookends

- Before implementation, confirm this feature worktree is current with `main` and
  re-read `docs/src/reference/openapi/index.md`, `docs/src/reference/contracts.md`,
  and `docs/src/client-server-interface.md` so the endpoint inventory starts from
  current contract docs.
- Before converting an endpoint group, capture the current generated OpenAPI and
  relevant bespoke OpenAPI snippets so response schema changes are reviewable.
- After each endpoint group conversion, update generated OpenAPI, tests, and docs
  in the same unit of work.
- Before completion, search for every converted route path across `docs/src/`,
  `packages/server/priv/static/openapi.yaml`, and `docs/src/reference/openapi/` to
  ensure the final docs identify exactly one canonical contract source.

## Risks And Tradeoffs

- Some controller APIs are workflow protocols rather than clean resource actions;
  forcing them into Ash can obscure behavior or create compatibility risk.
- Generated OpenAPI may expose schema details differently than hand-maintained
  docs, requiring careful review before removing bespoke references.
- Byte-for-byte compatibility may be expensive for endpoints with custom errors or
  status codes; each deviation needs explicit review.
- Migrating too many API groups at once can make regressions hard to isolate.
- Leaving too many retained controllers weakens the project goal unless each
  retained endpoint has a concrete rationale.

## Implementation Assumptions

- The first implementation should land one API group at a time behind this feature
  spec rather than converting all eligible endpoints in one large change.
- Runtime compatibility is stricter than schema aesthetics: generated OpenAPI may
  be organized differently, but runtime JSON, status codes, auth failures, and
  typed errors for existing consumers must remain compatible unless a versioned
  migration is explicitly documented.
- Retained-controller endpoints are acceptable only with route-specific rationale
  in the endpoint inventory and reference docs.
