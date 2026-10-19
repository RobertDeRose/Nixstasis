# Ash API Contract Unification

The APIs that outside clients use are now described by OpenAPI generated from Ash actions. The builder actions live
under `/api/json/builder_contract/*`, and every device action (listing, registration, heartbeat, command results, and
payload fetches) is also available under `/api/json/device_runtime/devices`.

The client still uses the `/api/v1` routes. Both sets of routes run the same code, so device authentication, status
codes, responses, rate limits, telemetry, command delivery, retries, and payloads behave the same either way. The
original plan is in the [design record](design.md).

## What changed for users

- **API clients** can find the builder and device action schemas in the committed, generated OpenAPI file.
- **Operators** can list devices through the generated route, with the same filters and permission checks.
- **Devices** can register, send heartbeats, report results, and fetch payloads through the generated routes, using
  the `deviceBearer` scheme.
- **Registration** is still public and is where a device gets its credentials. The other device routes check the
  device's bearer token, and report an unknown device, a missing or bad token, and an unapproved device in that order.
- **Existing `/api/v1` clients** see no change: `201` for registration, `200` for heartbeats and payloads, `202` for
  command results, and the same errors.
- **Not moved:** Caddy's certificate check, the E2E routes, and the development TLS diagnostics stay plain controller
  routes. Report previews have no generated route. The script workbench's records stay internal, with no create, read,
  update, or delete routes.

## How it fits in

Ash defines resources and actions where generated OpenAPI is genuinely useful. Each action hands off to the existing
contexts, `Nixstasis.Devices`, `Nixstasis.Monitoring`, `Nixstasis.Scripts`, and the command-policy code, and the
controllers are thin adapters, so the logic lives in one place.

The device routes are deliberately kept apart from the operator routes at `/api/json/devices`. `JsonApiPermissions`
looks up the device, checks its bearer token, sets the actor, and checks operator permissions for each route. The raw
device token is never passed into an Ash action. The client stays on `/api/v1` until a move to the generated routes
has been planned and reviewed on its own.

## Running it

The generated routes need no migration, client upgrade, or new settings. The registration security change (below)
does need clients and servers upgraded together, because clients must save their initial proof and replacement token
before registering.

For new Ash clients, use the committed generated OpenAPI. For existing clients that need `/api/v1` formats or status
codes, keep using the hand-written references.

The generated routes use the existing rate limits. Inventory reports are still untrusted, command policy is still
decided by the server, and fetching a payload has no side effects.

## Differences from the design

- **Added, not replaced.** The generated device routes sit alongside `/api/v1` instead of replacing it.
- **Different formats.** The generated routes use JSON:API, with their own documented security and status codes. The
  `/api/v1` routes keep their plain JSON and existing status codes.
- **Builder routes moved.** The old `/api/v1` builder routes were later removed, because nothing used them; the
  generated `/api/json/builder_contract/*` routes replace them.
- **No routes for scripts.** The six script workbench resources stay in Ash, but have no JSON:API routes, because plain
  create, update, and delete would skip the workbench's validation and audit trail.
- **Safer registration.** Registration now uses secrets the client prepares and saves first, so a lost response or a
  restart can recover. An approved exchange checks the proof, updates only device-owned fields, and swaps the stored
  hash in one step. Retrying with the committed replacement returns the same token without changing anything, and an
  old proof cannot be used again. A recovery file wins over an out-of-date identity. The client, both E2E
  registration callers, the generated OpenAPI, the hand-written device API reference, and the registration docs all
  follow this. It needed no database migration, and the server still stores no plain-text credentials.

## Not included

- The client does not use the generated device routes.
- Report export, the E2E API, and development diagnostics have no generated contracts.
- There are no external routes for script workbench actions.
- Browser LiveView routes, Caddy's certificate check, and the E2E workflow were not converted to Ash just for
  consistency.
- There is only one OpenAPI generator, Ash's.
- Inventory reports never trigger package installs or grant permissions on the device.

## Tests

- `packages/server/test/nixstasis_web/controllers/device_runtime_json_api_test.exs`: the generated device routes,
  including bearer authentication and the order of errors.
- `packages/server/test/nixstasis_web/controllers/builder_contract_json_api_test.exs` and
  `packages/server/test/nixstasis/schema_options/builder_contract_test.exs`: the generated builder actions.
- `packages/server/test/nixstasis_web/controllers/device_controller_test.exs`, `heartbeat_controller_test.exs`, and
  `device_command_controller_test.exs`: the unchanged `/api/v1` formats and status codes.
- `packages/server/test/nixstasis_web/openapi_contract_test.exs`: the generated OpenAPI.
- `packages/server/test/nixstasis/devices/enrollment_test.exs`: proof checks, the single-step swap, and retry recovery.
- `packages/client/internal/transport/register_test.go`, `security_test.go`, `client_runtime_test.go`, and
  `packages/client/cmd/nixstasis/register_test.go`: the client's `/api/v1` calls and registration recovery.
- `mix ash.codegen --check`, and `mix openapi.generate` matching the committed `packages/server/priv/static/openapi.yaml`.

## Related pages

- [Client-Server Interface](../../client-server-interface.md)
- [API & Runtime Contracts](../../reference/contracts.md)
- [OpenAPI Contracts](../../reference/openapi/index.md), including the generated
  `packages/server/priv/static/openapi.yaml` and the hand-written
  [Device API](../../reference/openapi/device-api.yaml) reference for `/api/v1`
- [Architecture Overview](../../architecture.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
- [Server Web](../../modules/server-web.md)
- [Server Devices](../../modules/server-devices.md)
- [Server E2E](../../development/e2e/server.md)
- [Server Reporting](../../modules/server-reporting.md)
- [Deployment](../../operations/deployment.md)
- The [endpoint inventory](endpoint-inventory.md) and [contract design](contract-design.md) worked out for this feature
