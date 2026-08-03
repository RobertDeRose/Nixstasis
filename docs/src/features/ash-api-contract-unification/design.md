<!-- workflow-migration:legacy-markdown-to-beads -->

# Ash API Contract Unification

## Summary

Move externally consumed, durable HTTP API contracts onto Ash-backed resources and
actions when the contract benefits from Ash-generated OpenAPI and the mapping
preserves existing behavior. Generated OpenAPI is the canonical reference for
those Ash-backed contracts instead of a duplicate hand-maintained schema.

This feature does not require every Phoenix route to use Ash. UI-only LiveView
interactions remain outside scope. Infrastructure-specific and workflow-specific
protocols may remain controller-owned when Ash would not provide a practical
benefit; their current contracts and rationale remain documented.

The device runtime used by Go clients is an explicit in-scope priority because it
is an externally consumed protocol that benefits from a discoverable,
contract-driven API.

## Source Of Intent

This spec is seeded from the `ash-api-contract-unification` entry in
`docs/src/planned-features.md`. The intended boundary is externally consumed API
contracts that benefit from generated OpenAPI and a well-defined Ash-backed
contract model, not UI-only routes or every internal HTTP handler.

## Goals

- Inventory every externally accessed non-UI endpoint under `/api/v1`,
  `/api/json`, `/e2e`, `/_nixstasis/laptop`, and related generated or
  hand-maintained API reference surfaces.
- Classify each endpoint as `ash-backed`, `retained-controller`, `ui-only`, or
  `deferred` before implementation.
- Convert externally consumed resource/action contracts to Ash resources,
  actions, or generated Ash JSON/OpenAPI routes where that improves contract
  discoverability without weakening runtime behavior.
- Prioritize the device runtime used by Go clients, preserving its wire,
  authentication, status, and side-effect contracts.
- Preserve existing contracts for Caddy domain approval, the current E2E harness,
  builder compatibility wrappers, and any deliberately retained workflow.
- Make generated OpenAPI canonical for `ash-backed` routes and keep retained
  controller contracts documented under `docs/src/reference/` with explicit
  route-specific rationale.
- Record gray areas, such as future report export APIs, as deferred decisions
  rather than forcing speculative conversions.

## Non-Goals

- Converting browser LiveView routes or UI-only interactions into API routes.
- Converting Caddy's `GET /api/v1/check_domain` protocol endpoint into Ash.
- Migrating the current E2E harness or redesigning its test/reporting model as
  part of this feature.
- Designing a report-export API before there is a concrete external consumer.
- Replacing Ash JSON/OpenAPI generation with a separate OpenAPI generator.
- Changing device runtime authentication, Caddy/AuthCrunch browser
  authentication, terminal authorization, or E2E enablement gates.
- Reworking production ingress, FRP runtime behavior, or deployment topology.
- Forcing a workflow or infrastructure protocol into Ash solely for architectural
  uniformity.

## Current Behavior

- The builder generic-action resource and generated `/api/json/builder_contract/*`
  routes already exist, alongside `/api/v1` compatibility wrappers.
- Existing operator/developer Ash resource groups are exposed through `/api/json`
  and the generated `packages/server/priv/static/openapi.yaml` artifact. The six
  script-workbench persistence resources remain Ash-owned but are domain-only;
  their generic CRUD routes are intentionally not exposed.
- The Go client remains on the bespoke `/api/v1` compatibility transport for
  registration, heartbeat, command results, and payload fetches during migration.
  The canonical generated target is the additive
  `/api/json/device_runtime/devices` route family with route-level operator,
  public-registration, and `deviceApiKey` security as defined in
  `contract-design.md`.
- Caddy, E2E, and development-diagnostic protocols remain controller-owned.
- Report result preview is controller-owned and has no confirmed external export
  consumer.
- API reference docs contain both generated OpenAPI and hand-maintained contracts,
  so route ownership and artifact freshness must be reconciled explicitly.

## Proposed Scope

In scope:

- A complete inventory of externally accessed non-UI routes and their consumers.
- Reconciliation of the already-delivered builder Ash routes, generated artifact,
  compatibility wrappers, authentication behavior, and documentation.
- Device runtime API resources/actions and generated contract coverage, preserving
  the Go client's existing wire and authentication behavior through compatibility
  wrappers or an explicitly versioned client migration.
- Endpoint request/response models, generated OpenAPI, retained-contract docs,
  and focused server/Go compatibility tests for each migrated group.
- Existing `/api/json` resource groups, including alert-rule APIs, where the
  generated Ash contract already exists and only inventory/documentation evidence
  is incomplete. Script-workbench persistence resources stay UI-only until an
  audited external contract is designed.

Out of scope for this feature:

- Browser-only LiveView interactions and UI controller actions.
- Caddy's Caddy-only TLS approval protocol.
- The current E2E harness conversion or a redesign of its test/reporting model.
- A report export API; the existing preview route remains unchanged pending a
  concrete external contract decision.
- Development-only laptop diagnostics as product OpenAPI contracts.

## Endpoint Classification Rules

Classify each endpoint into exactly one bucket before implementation:

- `ash-backed`: an externally consumed resource/action contract that benefits
  from Ash's model, action, authorization, and generated OpenAPI support. Its
  generated contract is canonical; a compatibility wrapper may remain when it
  preserves an existing client wire format.
- `retained-controller`: an infrastructure-specific or workflow-specific
  protocol where a Phoenix controller is the clearest current boundary or where
  conversion provides no practical benefit. It remains documented with a
  route-specific contract and rationale.
- `ui-only`: a browser or LiveView interaction with no durable external API
  contract. It is outside this feature.
- `deferred`: an externally useful contract whose future need, transport shape,
  or migration boundary is not established enough for this feature. It remains
  unchanged and requires a separate decision before conversion.

Initial classifications:

- Existing externally consumed `/api/json` resource groups and the builder
  generic-action routes are `ash-backed`; the builder `/api/v1` endpoints remain
  retained compatibility wrappers. Script-workbench persistence resources are
  `ui-only` domain resources: they remain Ash-owned, but their generic JSON:API
  routes and generated OpenAPI paths are intentionally absent because no external
  consumer exists and generic CRUD would bypass workflow boundaries.
- Device registration, heartbeat, command results, and command payload fetches
  are `ash-backed` priorities because Go clients consume them as a durable
  external protocol. Their device authentication and orchestration boundaries
  must be preserved.
- Caddy `GET /api/v1/check_domain` is `retained-controller`. It is a Caddy-only
  ingress protocol with no independent product API consumer.
- Current `/e2e` run, result, cancellation, and log routes are
  `retained-controller` for this feature. Their future OpenAPI value and test
  model can be reconsidered separately, but this feature does not force that
  work.
- The current report result preview route is `deferred` for Ash migration. It
  remains operationally unchanged until an external report/export contract is
  actually needed.
- `/_nixstasis/laptop/*` diagnostics are `retained-controller` development
  routes and must not be promoted into product OpenAPI guidance.

## Compatibility Requirements

- Device runtime registration, heartbeat, command result, and deferred payload
  behavior must preserve existing Go-client request/response shapes, status codes,
  API-key authentication, approval/token semantics, rate limits, telemetry,
  command delivery, and side effects unless a versioned client migration is
  explicitly documented.
- Existing Caddy `GET /api/v1/check_domain` behavior must remain compatible with
  the deployment Caddyfile; this route remains controller-owned.
- E2E harness endpoints must keep current enablement gates, lock semantics,
  idempotency behavior, and result submission contracts; this feature does not
  convert or redesign them.
- Builder API validation and schema lookup behavior must preserve existing error
  classes and response shapes. Generated `/api/json` authorization and legacy
  `/api/v1` wrapper authorization must be documented separately.
- Deferred report preview behavior must remain unchanged until a future external
  report/export contract is approved.
- Auth and authorization semantics for device API keys, bearer-protected Ash
  routes, AuthCrunch/Caddy headers, E2E gates, and operator-only endpoints must
  remain explicit and tested.

## Implementation Approach

1. Inventory routes from `packages/server/lib/nixstasis_web/router.ex` and map
   them to controllers, Ash resources/actions, consumers, generated OpenAPI paths,
   and reference docs. Include existing generated resource families and explicitly
   disposition Ash-owned domain resources whose generic routes are not supported,
   not only routes changed by this feature.
2. Rebaseline the already-delivered builder Ash routes and their `/api/v1`
   compatibility wrappers. Resolve generated-route authentication, wire-shape,
   status, and OpenAPI artifact evidence before adding another conversion.
3. Convert the device runtime one coherent group at a time. The approved target
   is `/api/json/device_runtime/devices`: an operator-gated filtered list, a public
   registration action, and API-key-gated heartbeat/command actions. Define the
   Ash actions, device-runtime permission plug, route-level OpenAPI security, and
   orchestration boundary first; preserve the existing device-authenticated
   `/api/v1` compatibility transport while generated coverage and Go-client tests
   are added.
4. Generate or refresh OpenAPI from Ash after each converted API group and verify
   that the served runtime specification and committed static artifact agree.
5. Remove duplicate hand-maintained OpenAPI sections only when generated OpenAPI
   covers the same external contract completely; retain wrapper-specific docs when
   the compatibility shape differs.
6. For retained controllers, document why the protocol remains outside Ash and
   keep its current contract under `docs/src/reference/`. For deferred contracts,
   record the future decision boundary without changing runtime behavior.
7. Reconcile docs and tests before marking the feature complete. Report export and
   E2E-contract redesign remain separate follow-up decisions.
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
- `packages/server/lib/nixstasis/devices/`
- `packages/server/lib/nixstasis/monitoring.ex`
- Ash resources and actions under `packages/server/lib/nixstasis/`
- `packages/client/internal/transport/`
- Server controller, domain, OpenAPI, and compatibility tests under
  `packages/server/test/`
- Go transport and runtime contract tests under `packages/client/`

## Validation

- Route inventory proves every non-UI API endpoint has a classification.
- The committed endpoint inventory reconciles every bespoke OpenAPI file with
  either generated Ash OpenAPI coverage or retained-controller rationale.
- Generated OpenAPI includes each endpoint converted to Ash-backed contracts.
- Tests prove converted endpoints preserve existing request/response shapes,
  status codes, validation errors, and authentication behavior.
- Go client transport tests continue to pass for registration, heartbeat, command
  polling, command results, and deferred payload fetches before and after each
  device migration group.
- Device API-key authentication, approval, telemetry, command delivery, and
  response-shape compatibility tests pass.
- E2E harness tests continue to pass for the retained `/e2e` contract; no E2E
  conversion is required by this feature.
- `mix ash.codegen --check` passes when Ash resources change.
- Ash/Ash JSON:API usage rules are consulted before implementing route/schema
  changes.
- `mix precommit` passes in `packages/server` after server changes.
- `mdbook build docs` passes after reference docs are reconciled.
- A final search confirms retained hand-maintained OpenAPI sections have explicit
  rationale and converted sections are not duplicated.

## Reconciliation Bookends

- Before implementation, confirm this feature worktree is current with `dev` and
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

- Device runtime conversion crosses API-key authentication, telemetry, command
  delivery, and compatibility boundaries; forcing a JSON:API transport without
  preserving those semantics could break every Go client.
- Some controller APIs are infrastructure or workflow protocols rather than clean
  resource actions; forcing Caddy or E2E into Ash would add complexity without a
  current contract benefit.
- Generated OpenAPI may expose schema details differently than hand-maintained
  docs, requiring careful review before removing bespoke references.
- Byte-for-byte compatibility may be expensive for endpoints with custom errors or
  status codes; each deviation needs explicit review.
- Migrating too many API groups at once can make regressions hard to isolate.
- Deferred report/export and E2E decisions must remain visible without expanding
  the current feature opportunistically.

## Implementation Assumptions

- The builder Ash slice is existing implementation to reconcile, not a second
  conversion pass.
- Device runtime is the first new implementation group and lands one coherent
  endpoint group at a time behind this feature spec.
- Runtime compatibility is stricter than schema aesthetics: generated OpenAPI may
  be organized differently, but runtime JSON, status codes, auth failures, and
  typed errors for existing consumers must remain compatible unless a versioned
  migration is explicitly documented.
- The device-runtime generated surface uses `deviceApiKey` as a query API-key
  scheme for heartbeat, command-result, and payload actions. Registration has no
  application key; the generated list uses the operator bearer boundary. The raw
  key is a permission-plug concern, not an Ash action argument.
- Retained-controller endpoints are acceptable when they have a route-specific
  infrastructure/workflow rationale and current contract documentation.
- Deferred endpoints remain unchanged until a separate external-consumer decision
  establishes their required contract.

## Metadata

- Beads feature root: `nixstasis-zf5`
- Feature slug: `ash-api-contract-unification`
- Base branch: `dev`
- Status: implemented; delivery action pending

## Feature Summary

Use Ash-generated models, actions, and OpenAPI for externally consumed API contracts
that benefit from a well-defined generated contract. Prioritize the device runtime
used by Go clients while retaining UI-only, Caddy-only, and current E2E workflow
routes where Ash provides no current benefit.

## User Intent

Client authors and maintainers need one discoverable contract source for APIs that
external consumers depend on. The device runtime is especially important because
Go clients communicate with the server through it. Caddy's protocol endpoint and
UI-only routes do not need Ash merely for uniformity; report export and E2E API
value remain future decisions.

## User-Facing Behavior

Generated builder and other Ash-backed contracts remain available through
`/api/json` and the generated OpenAPI artifact. The additive generated device
runtime family is `/api/json/device_runtime/devices`; existing `/api/v1`
compatibility wrappers, Caddy checks, E2E workflows, and retained diagnostics
preserve their current payloads, status codes, authentication, and workflow
behavior while the device runtime is migrated incrementally.

## Requirements

The endpoint inventory, classification rules, compatibility requirements, and
incremental implementation approach above are authoritative. A route moves to
Ash because it is an externally consumed contract that benefits from generated
OpenAPI and can preserve its behavior, not solely to satisfy architectural
uniformity.

## Proposed Design

Reconcile the existing builder implementation and generated artifacts, then
migrate the device runtime through Ash-backed actions/resources and generated
contract coverage one coherent endpoint group at a time. Keep Caddy and current
E2E protocols controller-owned, keep UI-only interactions outside scope, and defer
report export until an external contract is needed.

## Existing Context

Ash resources, generated OpenAPI, retained bespoke OpenAPI, Phoenix controllers,
the Go client, Caddy, and the E2E harness already own different HTTP surfaces.
The migration must connect these boundaries without replacing protocol-specific
authentication or workflow orchestration with generic CRUD.

## Architecture Consistency

Ash owns externally consumed resource/action contracts where generated OpenAPI
provides a concrete benefit. Context modules and thin compatibility controllers may
orchestrate Ash actions and preserve legacy transport/authentication. Controllers
remain appropriate for Caddy asks, E2E orchestration, development diagnostics, and
future report decisions when those boundaries are clearer than generated Ash
routes.

## Operational Considerations

Every device migration must preserve API-key authentication, authorization,
telemetry, command delivery, error semantics, and client compatibility. Caddy and
E2E gates remain unchanged. Generated OpenAPI must be reproducible and its runtime
and committed artifacts must not drift.

## Documentation Impact

Update `docs/src/reference/contracts.md`, `docs/src/reference/openapi/`,
`docs/src/client-server-interface.md`, and the server API module pages as each
endpoint group reaches a final owner. Keep explicit rationale for retained Caddy,
E2E, and diagnostic routes, and record the deferred report/export boundary.

## Validation Strategy

For each migrated group, diff generated OpenAPI and run focused Ash/domain,
controller, authorization, Go transport, compatibility, and documentation checks.
The device runtime must pass server and Go-client contract tests before its
compatibility wrapper or canonical generated route is considered complete.

## Implementation Decomposition

1. Reconcile the existing builder slice, route inventory, auth matrix, and generated
   OpenAPI artifact.
2. Define the device runtime Ash action/resource and orchestration boundary using
   `:list_runtime_devices`, `:register_runtime_device`, `:heartbeat`,
   `:acknowledge_command_results`, and `:fetch_command_payload`, with explicit
   route-level `deviceApiKey` security and the existing JSON:API permission
   pipeline dispatch.
3. Migrate device registration, heartbeat, command result, and payload contracts in
   bounded groups while preserving the existing client transport and observed
   replay/malformed-input behavior.
4. Regenerate OpenAPI, test server/Go compatibility, and reconcile docs after each
   group.
5. Keep Caddy/E2E/diagnostics retained and report export deferred.

## Dependencies and Parallelism

Inventory and documentation reconciliation can proceed after shared authentication
and error-shape rules are fixed. Device endpoint groups may be reviewed separately,
but generated OpenAPI, compatibility wrappers, and Go tests follow each group.

## Rejected Alternatives

A forced all-at-once conversion of every controller protocol, converting Caddy-only
or current E2E routes without a benefit case, and a second OpenAPI generator remain
rejected.

## Open Questions

No device-runtime boundary question remains open: action names, orchestration
ownership, generated route family, API-key security scheme, route-specific
authentication, compatibility wrapper, and error-precedence rules are defined in
`docs/src/features/ash-api-contract-unification/contract-design.md`. The remaining
work is implementation and evidence, not another boundary decision. Report export,
E2E generated-contract treatment, and development diagnostics remain deferred or
retained as listed below.

## Deferred Decisions

- Whether a future report export API warrants an Ash-backed contract.
- Whether the E2E harness should be redesigned or exposed as a generated contract.
- Whether any retained development diagnostic route ever becomes a supported
  external product API.
