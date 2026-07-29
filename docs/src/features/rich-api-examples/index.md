# Rich API Examples

## Delivery Summary

- Beads feature root: `nixstasis-jpl`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `a5b6eaf2f9fc22ad2567ebdb49671708f692614d`
- Design record: `design.md`

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

## Validation Evidence

The delivered examples were reconciled against server controller tests, Go transport tests, retained OpenAPI files, and
generated Ash OpenAPI. `docs/src/client-server-interface.md` is direct reader-facing evidence.

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

## Audit Trail

Legacy tasks were imported beneath `nixstasis-jpl`. Commit `a5b6eaf2f9fc22ad2567ebdb49671708f692614d`
directly reconciled the rich examples in the client-server contract documentation.
