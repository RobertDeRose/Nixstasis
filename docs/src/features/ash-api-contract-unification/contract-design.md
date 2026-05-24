# Ash API Contract Design Notes

These notes satisfy the contract-design pass before endpoint implementation. They
do not convert routes yet; they define the intended Ash model/action shape and
retained-controller rationale for the current endpoint inventory.

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

### Builder APIs

Candidate endpoints:

- `GET /api/v1/builder-schemas`
- `GET /api/v1/builder-schemas/:schema_id/versions/:schema_version/options`
- `POST /api/v1/builder-configurations/validate`

Proposed model:

- Introduce a non-persisted Ash resource, tentatively
  `Nixstasis.SchemaOptions.BuilderSchema`, for builder option and validation
  contracts. If implementation finds an existing durable schema-reference resource,
  use that resource instead and preserve the action names below.
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
- Keep authorization/access-denied behavior explicit; this builder slice has no
  route-level `403` contract and remains unauthenticated behind the shared API
  rate limiter, while `404` and `422` semantics stay documented and tested.

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

First implementation candidate: builder APIs, because they are compact,
non-client-critical, and have explicit OpenAPI request/response models.

### Device Runtime APIs

Candidate endpoints:

- `GET /api/v1/devices`
- `POST /api/v1/devices/register`
- `POST /api/v1/devices/:device_id/heartbeat`
- `POST /api/v1/devices/:device_id/command_results`
- `GET /api/v1/devices/:device_id/command_payloads/:ref`

Proposed model:

- Use `Nixstasis.Devices.Device` for list/register/heartbeat actions where the
  action semantics remain device-centric.
- Use `Nixstasis.Devices.PendingCommand` or action-specific Ash actions for
  command result acknowledgement and deferred payload fetches.
- Target `Device.read` or a filtered read action for `GET /api/v1/devices`,
  preserving filters `product`, `account_number`, `approval_status`,
  `connectivity_status`, and `ipv4_address`.
- Target `Device.register` for `POST /api/v1/devices/register`, preserving
  request fields `mac_address`, `product_name`, and dynamic `metadata`, and
  response fields currently emitted by `DeviceController.device_data/2`.
- Target `Device.heartbeat` for `POST /api/v1/devices/:device_id/heartbeat`,
  preserving telemetry and connection-status input plus response fields
  `remote_access_token` and `commands`.
- Target `PendingCommand.acknowledge_results` for command result submission,
  preserving the `results` array and `acknowledged_count` response.
- Target `PendingCommand.fetch_payload` for deferred command payload retrieval,
  preserving `content_type`, `name`, and `data`.
- Preserve Go client runtime compatibility exactly, including status codes,
  `api_key` query authentication behavior, pending/approved registration token
  behavior, heartbeat `remote_access_token`, command result acknowledgement, and
  command payload shape.
- Reconcile the undocumented `ipv4_address` device list filter before conversion.

Device runtime APIs are high risk because they are consumed by the Go client; do
not convert them before baseline compatibility tests and OpenAPI diff checks are
in place.

### Report Result API

Candidate endpoint:

- `GET /api/v1/reports/:id/results`

Proposed model:

- Add an Ash action on `Nixstasis.Reporting.CustomReport` or a reporting action
  wrapper that returns the current `{fields, rows}` response model.
- Target action name: `CustomReport.results`, requiring report `id` and returning
  `fields` as a string array and `rows` as an array of dynamic maps.
- Add a baseline controller test before conversion if none exists.
- Preserve report-not-found/result-unavailable behavior from `report-api.yaml`.

### Existing Ash JSON:API Resources

Existing route groups under `/api/json` remain generated Ash resource APIs:

- `devices`
- `pending_commands`
- `alerts`
- `alert_rules`
- `telemetry_events`
- `custom_reports`
- `system_settings`

These should not be rewritten as part of the first migration slice. They are the
generated target surface used to compare future converted contracts.

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

All `/e2e` endpoints remain controller-owned by default.

Rationale:

- The E2E surface is a gated protocol workflow with enablement checks,
  protocol-version headers, idempotent run reuse, environment locks, seed
  execution, result ingestion, log retention, and typed errors.
- Individual resource-like reads can be revisited later, but only after the
  workflow contract is proven safe to express through Ash actions.

## Response Schema Rules

- Generated OpenAPI may organize schemas differently from bespoke files, but
  runtime JSON, status codes, auth failures, and typed errors must remain
  compatible unless a versioned migration is documented.
- Converted endpoints must have tests for success, validation failure,
  authorization/authentication failure, and important edge cases before bespoke
  OpenAPI sections are removed.
- Retained endpoints must keep route-specific rationale in reference docs.
