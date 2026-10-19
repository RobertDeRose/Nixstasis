# Rich API Examples

The API documentation includes copyable examples of both successful and failed requests for the device, Caddy
certificate check, E2E, builder, report, and generated Ash JSON:API contracts. The original plan is in the
[design record](design.md).

## What changed for users

Client authors and operators can see realistic examples of registration, heartbeats, commands, repeated requests,
environment locks, validation errors, permission errors, cancellation, and missing logs, without reading the code to
work out the formats.

## How it fits in

Each example lives next to the contract it illustrates: in prose for the step-by-step device flows, in the hand-written
OpenAPI files for the controller APIs, and in the generated OpenAPI for Ash resources. Identities and credentials in
the examples are made up.

## Running it

This feature only changed documentation. When a controller, the client transport, or the generated OpenAPI changes,
review the matching examples too.

## Differences from the design

Command policy examples were added later, on the same page, as that feature grew.

## Not included

- Browser LiveView routes are not presented as public API.
- No API behavior changed.

## Tests

The examples are checked against the tests that define each format:

- Controller tests under `packages/server/test/nixstasis_web/controllers/`, including
  `provisioning_controller_test.exs`, `heartbeat_controller_test.exs`, `device_command_controller_test.exs`,
  `frp_authorization_controller_test.exs`, `e2e_run_controller_test.exs`, `e2e_run_result_controller_test.exs`,
  `builder_contract_json_api_test.exs`, and `report_result_controller_test.exs`.
- `packages/server/test/nixstasis_web/openapi_contract_test.exs`: the hand-written and generated OpenAPI.
- Go transport tests under `packages/client/internal/transport/`: `client_runtime_test.go` and `register_test.go`.

## Related pages

- [Client-Server Interface](../../client-server-interface.md)
- [API & Runtime Contracts](../../reference/contracts.md)
- [OpenAPI Contracts](../../reference/openapi/index.md)
