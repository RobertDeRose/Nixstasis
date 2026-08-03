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
- Use the existing read action `:list_schema_references` with no required
  arguments. Output items preserve the current `SchemaReference` fields:
  `schema_id`, `schema_version`, `product_name`, and `readable`.
- Use the existing read action `:options_for` with required arguments
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

### Builder Compatibility Matrix

The generated and compatibility routes intentionally expose different transport
contracts while sharing the same Ash/domain behavior:

| Surface                                                                              | Phoenix authorization boundary                                                | Success contract             | Error/status contract                                              |
|--------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|------------------------------|--------------------------------------------------------------------|
| `GET /api/json/builder_contract/schema_references`                                   | `JsonApiPermissions` report-view policy; bearer security in generated OpenAPI | `200`, raw JSON array        | `403` JSON:API error when permission is denied                     |
| `GET /api/json/builder_contract/schemas/:schema_id/versions/:schema_version/options` | `JsonApiPermissions` report-view policy; bearer security in generated OpenAPI | `200`, raw options object    | `400` invalid query, `403` permission denied, `404` missing schema |
| `POST /api/json/builder_contract/builder_configurations/validate`                    | `JsonApiPermissions` report-view policy; bearer security in generated OpenAPI | `201`, raw validation object | `400` invalid JSON:API body, `403` permission denied               |
| `GET /api/v1/builder-schemas`                                                        | `/api/v1` `:api` pipeline and rate limiter; no JSON:API permission plug       | `200`, `{"data": [...]}`     | Legacy wrapper behavior                                            |
| `GET /api/v1/builder-schemas/:schema_id/versions/:schema_version/options`            | `/api/v1` `:api` pipeline and rate limiter; deployment-edge auth is separate  | `200`, `{"data": ...}`       | `404` `schema_not_found`, `422` invalid request                    |
| `POST /api/v1/builder-configurations/validate`                                       | `/api/v1` `:api` pipeline and rate limiter; deployment-edge auth is separate  | `200`, raw validation object | `422` `invalid_validation_payload`                                 |

The generated contract is canonical for Ash action fields and OpenAPI. The
`/api/v1` wrappers remain a separate compatibility surface because their JSON
shape, status codes, and Phoenix pipeline differ.

### Device Runtime APIs

Candidate endpoints:

- `GET /api/v1/devices`
- `POST /api/v1/devices/register`
- `POST /api/v1/devices/:device_id/heartbeat`
- `POST /api/v1/devices/:device_id/command_results`
- `GET /api/v1/devices/:device_id/command_payloads/:ref`

The device runtime is the next Ash-backed implementation group, not a deferred
candidate. The contract is split into an Ash-generated surface and an unchanged
compatibility surface so the Go client does not need an unversioned migration.

#### Ash ownership and orchestration boundary

- `Nixstasis.Devices.Device` owns the persisted device resource and the existing
  `:read` and `:register` Ash actions. Registration remains a domain action rather
  than generic device creation because it validates the public schema, preserves
  the MAC identity/approval state, and issues a token only after an approved
  result.
- The generated runtime action boundary uses five explicit non-CRUD action names:
  `:list_runtime_devices`, `:register_runtime_device`, `:heartbeat`,
  `:acknowledge_command_results`, and `:fetch_command_payload`. The first two
  adapt `Device.read`/`Device.register` and `Devices` normalization; the latter
  three delegate to the existing orchestration contexts. Their Ash action inputs
  and outputs must be explicit in generated OpenAPI.
- `Nixstasis.Devices` owns registration normalization and token issuance,
  device lookup/authentication, list filter normalization, pending-command
  claiming/acknowledgement, and deferred-payload extraction.
- `Nixstasis.Monitoring` remains the heartbeat orchestrator. The heartbeat action
  delegates to it for last-seen updates, sanitized telemetry persistence,
  best-effort inventory persistence, offline-alert resolution, rule evaluation,
  and pending-command delivery. `Nixstasis.Scripts` and
  `Nixstasis.CommandAllowlists` retain command-result side effects.
- The web layer owns only transport adaptation: parsing the legacy body/query
  shape, selecting the compatibility status/error envelope, and delegating to
  the Ash/domain action. It must not reimplement authentication or workflow
  side effects in each controller.

#### Generated transport and security decision

The canonical generated target is an additive Ash JSON:API route family under
`/api/json/device_runtime/devices`. It is intentionally separate from the
operator CRUD family at `/api/json/devices`:

| Generated route                                                           | Ash/domain boundary                                                                                                 | Authentication                                                                          |
|---------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------|
| `GET /api/json/device_runtime/devices`                                    | `:list_runtime_devices`, which adapts `Devices.list_devices/1` and returns normalized active-filter metadata.       | Operator bearer/device-view permission; this is not a device-runtime API-key operation. |
| `POST /api/json/device_runtime/devices/register`                          | `:register_runtime_device`, which calls `Device.register` through public normalization and approved-token issuance. | No application API key; deployment-edge protection remains separate.                    |
| `POST /api/json/device_runtime/devices/{device_id}/heartbeat`             | `:heartbeat`, delegating to `Monitoring.heartbeat/2`.                                                               | `deviceApiKey` query security.                                                          |
| `POST /api/json/device_runtime/devices/{device_id}/command_results`       | `:acknowledge_command_results`, with `Scripts` and `CommandAllowlists` ingestion.                                   | `deviceApiKey` query security.                                                          |
| `GET /api/json/device_runtime/devices/{device_id}/command_payloads/{ref}` | `:fetch_command_payload`, backed by `Devices.get_command_payload/2`.                                                | `deviceApiKey` query security.                                                          |

The generated family uses the Ash JSON:API media type and an explicit OpenAPI
schema for each action. POST action inputs are JSON:API `data` objects; the
compatibility wrappers continue to accept their current plain JSON objects. The
required generated inputs are `mac_address` plus `schema_definition` or legacy
`schema` for registration; `telemetry`, `connection_status`, and optional
`command_inventory` for heartbeat; and a required `results` array for command
acknowledgement. List filters are query inputs (`product`, `account_number`,
`approval_status`, `connectivity_status`, and `ipv4_address`); payload fetch uses
`device_id` and `ref` path inputs. These are generic Ash action routes, not generic
CRUD:
`list_runtime_devices` returns the logical `data` collection and normalized
`meta.active_filters`; `register_runtime_device` returns the logical registration
fields and optional token; `heartbeat` returns `data.commands` plus optional probe
and remote-access fields; `acknowledge_command_results` returns
`data.acknowledged_count`; and `fetch_command_payload` returns the raw payload
fields. Generated action routes explicitly set statuses `200`, `201`, `200`,
`202`, and `200` respectively, and use JSON:API error documents for auth,
validation, and not-found failures. The current `/api/v1` paths remain the
compatibility transport with their exact `application/json` body/status/error
behavior. Both surfaces call the same Ash/domain boundary; the Go client remains
on `/api/v1` until a separately reviewed client migration is approved.

`deviceApiKey` is the route-level generated OpenAPI security scheme:
`type: apiKey`, `in: query`, `name: api_key`. The existing `/api/json` pipeline
must dispatch these paths explicitly before its generic `JsonApiPermissions`
policy: `GET` list uses the existing operator bearer/device-view check,
`POST .../register` is an application-level public exception, and the three
runtime actions fetch the device and authenticate the query key. The permission
boundary sets the authenticated device with `Ash.PlugHelpers.set_actor/2` (and
context when needed) before forwarding to `AshJsonApiRouter`; the raw key is never
an action argument. It must preserve error precedence: unknown device `404`,
missing/invalid key `401`, and unapproved device `403`. `security: []` in generated
OpenAPI documents the registration exception; it does not bypass the Plug. The
`/api/v1` controllers retain the same lookup and error precedence during the
transition.

**Implementation handoff:** `.7.40` implements the explicit `device_runtime`
dispatch in the existing JSON API pipeline, including the public registration
exception, operator list policy, device lookup/API-key validation,
`Ash.PlugHelpers.set_actor/2`, and HTTP/direct tests for `404`/`401`/`403`
precedence. The list and registration generated routes are enabled by `.7.40`.
`.7.41` adds the generated heartbeat orchestration action, 200 response,
heartbeat-rate-limit classification, and OpenAPI/runtime coverage while reusing
this branch. `.7.42` must reuse the same branch for command results and payloads;
its remaining work is action/orchestration implementation and OpenAPI coverage.

Both generated and compatibility routes use the existing API rate limiter:
heartbeat is 30 requests per 60 seconds per device identity and other API routes
are 120 requests per 60 seconds. The generated heartbeat path is included in
heartbeat detection and uses the same 30-request limit. The committed
`docs/src/reference/openapi/device-api.yaml` remains the reference for the
compatibility paths until each generated path has runtime tests and appears in
the generated static artifact; duplicate hand-maintained sections are removed
only after that evidence exists.

#### Current `/api/v1` compatibility contract

The following behavior is the baseline that every generated action and wrapper
must preserve at the domain/side-effect level:

- **List — `GET /api/v1/devices`:** the current `:api` pipeline has no
  application-level authentication (deployment-edge protection is separate) and
  uses the 120/60-second limit. `Devices.list_devices/1` applies exact product,
  account, approval, connectivity, and `ipv4_address` filters. Connectivity is
  online when `last_seen_at` is within five minutes and offline when it is older
  or nil. Success is `200` with `{"data": [...], "meta": {"active_filters": ...}}`;
  filter values are normalized before being echoed. The route has no mutation
  side effects and returns `429` when its 120/60-second limit is exceeded.
- **Registration — `POST /api/v1/devices/register`:** the current `:api`
  pipeline has no device API-key requirement and uses the 120/60-second limit.
  `schema_definition` is copied to `schema`; `schema` is the legacy alias; public
  registration requires a schema with `product`; and `ipv4_address` may be taken
  from either the direct field or `metadata.ip_address`. The Ash upsert is by MAC
  and preserves `id` and `approval_status` during persistence. An approved
  re-registration then rotates the token hash and returns the new `api_token`; a
  pending device receives no token. Success is `201` with `data` containing the
  device fields and the token only when the resulting device is approved. Invalid
  or missing schema and Ash validation failures are `422` errors; the route also
  returns `429` when its 120/60-second limit is exceeded.
- **Heartbeat — `POST /api/v1/devices/:device_id/heartbeat`:** the controller
  fetches the device before authenticating `api_key`; approved devices require a
  secure token match. The route is limited to 30/60 seconds per device. A
  successful `200` response contains `data.commands` and may contain the
  server-owned `command_inventory_probe` and the FRPS `remote_access_token`.
  Telemetry is sanitized so top-level and nested `command_inventory` do not enter
  the telemetry event; inventory is persisted separately and malformed inventory
  is best effort. The heartbeat updates last-seen state, resolves offline alerts,
  evaluates rules, and claims at most 50 queued pending commands in FIFO order.
  Failure classes are `404` device-not-found, `401` missing/invalid key, `403`
  unapproved device, `422` heartbeat failure, and `429` rate limit.
- **Command results — `POST /api/v1/devices/:device_id/command_results`:** the
  request requires a list under `results`; success is `202` with
  `data.acknowledged_count`. Scripts and command-policy consumers ingest results
  before matching pending commands are acknowledged. Unknown or non-matching
  command IDs are ignored. A repeated ID currently re-reads an already-acked
  pending command, merges the result again, and increments the acknowledgement
  count; this is the observed compatibility behavior, not an idempotency guarantee.
  Missing/invalid keys, unknown devices, and unapproved devices retain
  `401`/`404`/`403`; a non-list body is `400`. The current controller has no
  reachable `422` processing-error branch for a list input, so `.7.42` must not
  invent one or silently change replay behavior; any future hardening requires an
  explicit versioned contract decision. The route returns `429` when its
  120/60-second limit is exceeded.
- **Deferred payload — `GET /api/v1/devices/:device_id/command_payloads/:ref`:**
  lookup and API-key authentication use the same precedence and `120/60-second`
  route limit. Success is `200` with the raw `{content_type, name, data}` payload;
  missing device or payload is `404`, missing/invalid key is `401`, and an
  unapproved device is `403`. Fetching a payload has no command acknowledgement
  side effect; rate limiting returns `429`.

The required baseline is covered by the server controller/domain tests and the
Go transport tests before each conversion group. Source references are the five
routes in `packages/server/lib/nixstasis_web/router.ex`,
`DeviceController`, `HeartbeatController`, `DeviceCommandController`,
`Nixstasis.Devices`, `Nixstasis.Monitoring`,
`packages/client/internal/transport/client.go`, and the focused tests under
`packages/server/test/nixstasis_web/controllers/` plus
`packages/client/internal/transport/`.

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

These route groups remain generated Ash resource APIs under `/api/json`:

- `devices`
- `pending_commands`
- `alerts`
- `alert_rules`
- `telemetry_events`
- `custom_reports`
- `system_settings`

The existing resource groups are not rewritten as part of the device migration,
but their inventory, authorization, generated/static OpenAPI, and route-test
evidence must remain reconciled. The six script persistence resources remain
Ash-owned for the LiveView workbench, but their generic JSON:API routes are
intentionally absent. The workbench calls the domain directly, and generic CRUD
would bypass validation, command dispatch, and audit boundaries. A future
external script contract requires audited domain-specific actions and a new
design decision.

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
