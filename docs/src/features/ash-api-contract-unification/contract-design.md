# Ash API Contract Design Notes

These notes define the Ash model/action shape, compatibility boundaries, and
retained-controller rationale for the current endpoint inventory. The builder
contract slice already exists and is being rebaselined here; device runtime
conversion is the next implementation priority.

## Usage Rule Consultation

- Read in-repo usage rules from `packages/server/deps/ash/usage-rules.md`,
  `packages/server/deps/ash_json_api/usage-rules.md`, and
  `packages/server/deps/ash_phoenix/usage-rules.md` after fetching server
  dependencies.
- Ash guidance used here: organize around domains/resources, create
  domain-specific actions instead of generic CRUD-only behavior, put business
  logic inside actions, use action arguments for validated inputs, and prefer
  domain code interfaces over direct `Ash.*` calls from web modules.
- AshJsonApi guidance used here: expose resources through the domain `json_api`
  block and resource `json_api` definitions; JSON:API route types include `get`,
  `index`, `post`, `patch`, and `delete` with standard JSON:API filter/sort/page
  semantics.
- AshPhoenix guidance is mostly UI/form-oriented for this feature. It reinforces
  using domain code interfaces and generated helpers rather than bypassing Ash
  through direct web-module calls.
- HexDocs MCP fetches were attempted first but local embedding generation was
  unavailable; the in-repo usage rules are the authoritative guidance for this
  design pass.

## Ash-Backed Endpoint Model

### Builder APIs (existing implementation)

Existing compatibility and generated endpoints:

- `GET /api/v1/builder-schemas`
- `GET /api/v1/builder-schemas/:schema_id/versions/:schema_version/options`
- `POST /api/v1/builder-configurations/validate`

Implemented model:

- Use the existing non-persisted Ash resource
  `Nixstasis.SchemaOptions.BuilderContract` for builder option and validation
  contracts. Preserve the action names and domain fields below.
- Add a read action `:list_builder_schemas` with no required arguments. Output
  items preserve the current `SchemaReference` fields: `schema_id`,
  `schema_version`, `product_name`, and `readable`.
- Add a read action `:builder_schema_options` with required arguments
  `schema_id` and `schema_version`, plus an optional `builder` argument that
  defaults to `alert`. The `builder` argument is the existing enum string
  `alert` or `report`. Successful output includes the
  `SchemaOptionsResponse` fields `schema_id`, `schema_version`, `builder`,
  `options`, and `load_time_ms`; each option preserves `key`, `label`,
  `value_type`, `order_index`, and `selectable`. The legacy `/api/v1` wrapper
  continues to expose that exact response body, while the generated Ash JSON:API
  route exposes the same successful payload fields and uses JSON:API error
  documents for missing or invalid requests.
- Add an action `:validate_builder_configuration` with required request fields
  `builder`, `schema_id`, `schema_version`, and `selections`. Each selection
  preserves `slot_id` and `selected_key`. Output preserves `ValidationResponse`:
  `valid`, `issues`, and `cleared_slot_ids`; each issue preserves `issue_code`,
  `message`, `slot_id`, and `blocking`.
- Expose these through generated Ash OpenAPI, preferring Ash JSON:API route/action
  support when it can preserve the current wire shape.
  If Ash JSON:API cannot preserve the wire shape, use Ash-backed actions behind a
  thin controller and keep generated schemas as canonical while documenting the
  controller transport wrapper.
- Preserve the existing `/api/v1` response models from `builder-api.yaml`:
  `SchemaReference`, `SchemaOptionsResponse`, `ValidationRequest`,
  `ValidationResponse`, and `ValidationIssue`. Generated `/api/json` routes may
  use JSON:API transport envelopes and error documents, but must keep the domain
  fields and status-code semantics explicit.
- Keep authorization/access-denied behavior explicit. The generated
  `/api/json/builder_contract/*` routes run through the JSON API permission
  pipeline and bearer security, while the `/api/v1` wrappers retain their
  compatibility-pipeline behavior. Document and test these as separate contracts;
  `404`, `422`, and generated `403` semantics must remain explicit.

Implementation note: the first builder slice uses
`Nixstasis.SchemaOptions.BuilderContract` as a non-persisted generic-action
resource. Existing `/api/v1` routes remain the compatibility transport, while
generated Ash JSON:API routes under `/api/json/builder_contract/*` publish the
Ash-backed action contracts in `packages/server/priv/static/openapi.yaml`. The
generated routes are Ash generic-action RPC endpoints hosted by the Ash JSON:API
router: successful generic-action responses use raw action payloads, and POST
generic actions use Ash JSON:API's generated `201` success status even when the
action validates rather than creates data. `/api/v1` remains the compatibility
surface for clients that require the original wrapper status/body shape.

The builder slice is existing implementation, not a future conversion candidate.
Its remaining work is to reconcile route-specific authorization, generated/static
OpenAPI evidence, wrapper parity, and reader-facing documentation before the
feature moves on to device runtime migration.

### Device Runtime APIs

Candidate endpoints:

- `GET /api/v1/devices`
- `POST /api/v1/devices/register`
- `POST /api/v1/devices/:device_id/heartbeat`
- `POST /api/v1/devices/:device_id/command_results`
- `GET /api/v1/devices/:device_id/command_payloads/:ref`

Proposed model:

- Treat the device runtime as the next Ash-backed implementation group, not as a
  deferred candidate. First capture the existing wire/auth/status/side-effect
  contract and define the domain orchestration boundary.
- Use `Nixstasis.Devices.Device` for device-centric registration and read actions.
  Use domain-specific actions around `Devices` and `PendingCommand` for runtime
  operations rather than modeling heartbeat and command delivery as simple CRUD.
- Target `Device.read` or a filtered read action for `GET /api/v1/devices`,
  preserving filters `product`, `account_number`, `approval_status`,
  `connectivity_status`, and `ipv4_address`.
- Target `Device.register` for `POST /api/v1/devices/register`, preserving
  request fields `mac_address`, `product_name`, and dynamic `metadata`, and
  response fields currently emitted by `DeviceController.device_data/2`.
- Add a heartbeat action or orchestration action that owns the existing
  `Monitoring.heartbeat/2` behavior, preserving telemetry, inventory,
  offline-alert resolution, command delivery, rate limits, and
  `remote_access_token`/`commands` responses.
- Add domain-specific command-result acknowledgement and deferred-payload
  actions, preserving the `results` array, `acknowledged_count`,
  `content_type`, `name`, and `data`.
- Preserve Go client runtime compatibility exactly, including status codes,
  `api_key` query authentication, pending/approved registration tokens, heartbeat
  responses, command result acknowledgement, and command payload shape.
- Publish generated OpenAPI coverage where it can represent the device contract;
  retain a thin `/api/v1` compatibility wrapper when existing transport or
  device-authenticated semantics cannot be replaced without a versioned client
  migration.
- Reconcile the undocumented `ipv4_address` device list filter before conversion.

Device runtime APIs are high risk because they are consumed by the Go client.
Baseline compatibility tests, OpenAPI diffs, and explicit authentication design
must precede each conversion group.

### Report Result API

Current route:

- `GET /api/v1/reports/:id/results`

This route is deferred for Ash migration. Reports currently need LiveView preview
behavior, while a future export or external reporting consumer may justify an
Ash-backed action. Do not add `CustomReport.results` in this feature without an
approved external contract. Keep the current `{fields, rows}` shape,
not-found/result-unavailable behavior, bespoke OpenAPI, and a baseline controller
test visible for that future decision.

### Existing Ash JSON:API Resources

Existing route groups under `/api/json` remain generated Ash resource APIs:

- `devices`
- `pending_commands`
- `script_drafts`
- `script_versions`
- `script_validation_runs`
- `script_test_runs`
- `script_deployment_runs`
- `script_client_actions`
- `alerts`
- `alert_rules`
- `telemetry_events`
- `custom_reports`
- `system_settings`

The existing resource groups are not rewritten as part of the device migration,
but their inventory, authorization, generated/static OpenAPI, and route-test
evidence must be reconciled. The six script groups are currently declared by
`Nixstasis.Domain` but absent from the committed static OpenAPI artifact; that
artifact/ownership mismatch must be resolved before inventory completeness is
claimed.

## Retained Controller Rationale

### Caddy TLS Approval

`GET /api/v1/check_domain` remains controller-owned by default.

Rationale:

- It is an ingress ask workflow called by Caddy, not a resource CRUD contract.
- The response contract is intentionally simple and deployment-coupled.
- Keeping it in `TLSController` makes the runtime boundary visible in Caddy and
  deployment docs.

### Development Laptop TLS Diagnostics

`GET /_nixstasis/laptop/tls_observations` and
`DELETE /_nixstasis/laptop/tls_observations` remain controller-owned.

Rationale:

- They are development-harness diagnostics, not production product APIs.
- Moving them into generated product OpenAPI could imply unsupported production
  semantics.

### E2E API

All `/e2e` endpoints remain controller-owned for this feature.

Rationale:

- The E2E surface is a gated protocol workflow with enablement checks,
  protocol-version headers, idempotent run reuse, environment locks, seed
  execution, result ingestion, log retention, and typed errors.
- The current E2E tests and reporting model may need a separate design review;
  this feature records the existing contract but does not spend migration effort
  on generated OpenAPI for it.

## Response Schema Rules

- Generated OpenAPI may organize schemas differently from bespoke files, but
  runtime JSON, status codes, auth failures, and typed errors must remain
  compatible unless a versioned migration is documented.
- Converted endpoints must have tests for success, validation failure,
  authorization/authentication failure, and important edge cases before bespoke
  OpenAPI sections are removed.
- Generated `/api/json` authorization and `/api/v1` compatibility authorization
  are separate contract surfaces and must be documented/tested separately.
- Retained endpoints must keep route-specific rationale in reference docs.
- Deferred endpoints must keep their current contract and an explicit future
  decision boundary; deferral is not permission to remove existing docs/tests.
