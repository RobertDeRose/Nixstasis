# Rich API Examples Design

## Summary

Add example-rich API documentation for the maintained Nixstasis HTTP contracts.
The feature adds representative request and response examples for successful
calls, validation errors, authorization failures, conflict or lock behavior, and
important edge cases across bespoke `/api/v1`, `/e2e`, generated Ash `/api/json`,
and retained hand-maintained OpenAPI surfaces.

## Source Of Intent

This feature is planned in `docs/src/planned-features.md` as
`rich-api-examples`.

## Goals

- Document realistic example payloads for device registration, pending approval,
  approved credential issuance, heartbeat, command delivery, command result
  submission, deferred command payload fetches, and Caddy `check_domain`
  decisions.
- Document realistic example payloads for E2E run creation, idempotent reuse,
  environment lock conflicts, protocol mismatch, seed failures, result
  submission, cancellation, and missing or pruned logs.
- Document examples for builder schema option lookup, validation success,
  validation failure, stale selections, missing schemas, and authorization
  failures where the current implementation exposes those outcomes.
- Document examples for report API surfaces that remain hand-maintained outside
  generated Ash OpenAPI, and link alert-rule examples to the generated Ash
  `/api/json/alert_rules` OpenAPI surface.
- Keep prose examples and OpenAPI examples synchronized by using one canonical
  source per API surface or explicit links between duplicated examples.

## Non-Goals

- Replace generated Ash OpenAPI.
- Change API behavior, status codes, routes, payload fields, or authentication
  semantics.
- Create exhaustive tutorials for every LiveView browser route.
- Invent examples for behavior that is not implemented or tested.

## Constraints

- Examples must use fake hostnames, fake tokens, fake device identifiers, and
  fake operator data.
- Examples must distinguish generated Ash `/api/json` documentation from bespoke
  `/api/v1` and `/e2e` controller contracts.
- Examples must cite or be checked against current controller tests, client
  transport tests, generated OpenAPI, or implementation code.
- Hand-maintained OpenAPI files under `docs/src/reference/openapi/` remain the
  source of truth only for retained bespoke contracts that are not fully covered
  by generated Ash OpenAPI.

## Affected Documentation

- `docs/src/client-server-interface.md`
- `docs/src/reference/openapi/`
- `docs/src/reference/openapi/index.md`
- `docs/src/reference/contracts.md`
- `packages/server/priv/static/openapi.yaml`

## Design

### Example Organization

Add examples where API readers already look for the contract:

- Put prose examples for device runtime APIs in `docs/src/client-server-interface.md`.
- Put examples for bespoke OpenAPI YAML contracts in their retained files under
  `docs/src/reference/openapi/`.
- Link generated Ash `/api/json` examples to `packages/server/priv/static/openapi.yaml`
  when the generated document already contains the example shape.
- Add prose only when the generated or hand-maintained OpenAPI file is not the
  clearest place to explain stateful behavior.

### Device Runtime Examples

Device examples should cover these flows without changing the contract:

- Registration request with fake device identity data.
- Registration response for pending approval.
- Registration or follow-up response after approval with issued runtime
  credentials, when supported by current tests and controllers.
- Heartbeat request with representative telemetry and script results.
- Heartbeat response with no commands and no remote-access token.
- Heartbeat response with command delivery.
- Heartbeat response with deferred payload metadata.
- Command result submission for success and failure.
- Deferred command payload fetch success and not-found or unauthorized failure.
- Caddy `check_domain` allow and deny decisions.

### E2E Examples

E2E examples should cover stateful API outcomes that test harness authors need:

- Run creation success.
- Idempotent reuse of an existing run.
- Environment lock conflict.
- Protocol mismatch.
- Seed failure response.
- Result submission success.
- Cancellation request.
- Missing or pruned log response.

### Builder, Report, And Alert Examples

Builder examples should prefer generated Ash OpenAPI examples when available.
Retained bespoke examples should be added only where the current documentation
keeps the contract outside generated Ash OpenAPI.

Report examples should cover the maintained bespoke report result preview API in
`docs/src/reference/openapi/report-api.yaml`.

Alert-rule examples should not be added as bespoke `/api/v1` examples because
current alert-rule HTTP resources are generated Ash JSON:API routes under
`/api/json/alert_rules`. Link to or extend generated OpenAPI examples for alert
rules instead of creating retained hand-maintained alert-rule contracts.

The examples should avoid documenting LiveView-only browser interaction details
as HTTP API contracts.

### Validation Strategy

Validation should prove examples match current behavior without making the docs
feature a behavior-changing implementation feature:

- Compare examples against controller tests and client transport tests.
- Inspect generated `packages/server/priv/static/openapi.yaml` for Ash-backed
  examples and route naming, including `/api/json/alert_rules`.
- Run `mdbook build docs`.
- Run OpenAPI validation for edited hand-maintained YAML files where the project
  already has a practical validation command.

## Success Criteria

- API consumers can copy representative request and response shapes for every
  maintained durable runtime API surface included in this feature.
- Error examples cover common validation, authorization, conflict, and missing
  resource failures that consumers must handle.
- Generated Ash examples and hand-maintained examples are clearly separated.
- `mdbook build docs` succeeds.
- OpenAPI references remain linked from the Reference section.

## Risks And Tradeoffs

- Examples can drift if they duplicate controller behavior without being tied to
  tests or generated OpenAPI.
- Too many examples can obscure the canonical contract unless they are organized
  by API surface and outcome.
- Hand-maintained examples add review burden when routes migrate between bespoke
  controllers and Ash-backed generated OpenAPI.

## Dependencies

- `docs/src/client-server-interface.md`
- `docs/src/reference/openapi/`
- `packages/server/priv/static/openapi.yaml`
- `packages/server/lib/nixstasis_web/controllers/`
- `packages/server/test/nixstasis_web/controllers/`
- `packages/client/internal/transport/client.go`
- `packages/client/internal/transport/*_test.go`
