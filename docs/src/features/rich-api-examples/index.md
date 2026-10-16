# Rich API Examples

## References

- Beads feature root: `nixstasis-jpl`
- Design record: [design.md](design.md)

## Delivered Capability

Nixstasis API documentation includes copyable success and failure examples for device runtime, Caddy approval, E2E,
builder, report, and generated Ash JSON:API contracts.

## User-Facing Behavior

Client authors and operators can inspect realistic registration, heartbeat, command, idempotency, lock, validation,
authorization, cancellation, and unavailable-log responses without inferring wire shapes from implementation code.

## Design Integration

Examples remain with their canonical contract owners: prose for stateful device flows, retained OpenAPI for bespoke
controllers, and generated OpenAPI for Ash resources. Fake identities and credentials avoid leaking operational data.

## Operational Impact

The feature changes documentation only. Contract examples must continue to be reviewed with controller tests, client
transport tests, and generated OpenAPI changes.

## Reference and Contracts

- [Client-Server Interface](../../client-server-interface.md)
- [API and Runtime Contracts](../../reference/contracts.md)
- [OpenAPI Contracts](../../reference/openapi/index.md)

## Test Coverage

The examples are documentation; they are checked against the tests that own each wire shape:

- Server controller tests under `packages/server/test/nixstasis_web/controllers/`, including
  `provisioning_controller_test.exs`, `heartbeat_controller_test.exs`, `device_command_controller_test.exs`,
  `frp_authorization_controller_test.exs`, `e2e_run_controller_test.exs`, `e2e_run_result_controller_test.exs`,
  `builder_schema_controller_test.exs`, `builder_config_validation_controller_test.exs`, and
  `report_result_controller_test.exs`.
- `packages/server/test/nixstasis_web/openapi_contract_test.exs`: retained and generated OpenAPI contracts.
- Go transport tests under `packages/client/internal/transport/`: `client_runtime_test.go` and `register_test.go`.

## Design Reconciliation

### Delivered as Designed

Examples cover the maintained API surfaces and distinguish generated from bespoke contract ownership.

### Intentional Changes

Later command-policy examples were added to the same contract page as that runtime capability evolved.

### Deferred Work

Future API surfaces must add their own evidence-backed examples when delivered.

### Rejected or Removed Scope

No LiveView browser routes were presented as public HTTP API contracts, and no API behavior changed.

## Documentation Updated

- `docs/src/client-server-interface.md`
- `docs/src/reference/contracts.md`
- `docs/src/reference/openapi/index.md`
- `docs/src/reference/openapi/*.yaml`
