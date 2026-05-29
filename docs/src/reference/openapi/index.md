# OpenAPI Contracts

The Ash-generated OpenAPI file at `packages/server/priv/static/openapi.yaml`
documents the Ash JSON:API surface under `/api/json`. This includes the
generated builder action routes under `/api/json/builder_contract/*`.

Phoenix controller APIs used by the Go client, legacy builder UI compatibility,
TLS approval, report previews, and E2E harness are bespoke routes, so their
wire-compatible controller contracts live here.

Generated Ash JSON:API request and response shapes, including alert-rule
contracts for `/api/json/alert_rules`, remain in
`packages/server/priv/static/openapi.yaml`.

## Contracts

- [Device API](device-api.yaml): registration, heartbeat, command results,
  deferred command payloads, device list filtering, and TLS domain approval.
- [Builder API](builder-api.yaml): legacy `/api/v1` compatibility wrappers for
  schema option lookup and builder selection validation. Generated Ash action
  contracts for the same behavior are in `packages/server/priv/static/openapi.yaml`.
- [Report API](report-api.yaml): custom report result preview data.
- [E2E API](e2e-api.yaml): E2E run lifecycle, results, logs, cancellation, and
  protocol-version requirements.

## Maintenance Notes

- Keep these contracts aligned with `docs/src/client-server-interface.md` and
  the Phoenix router/controller modules.
- Do not duplicate Ash JSON:API resources here unless a bespoke `/api/v1` or
  `/e2e` controller owns the route.
- Keep the builder `/api/v1` contract here until all consumers can use the
  generated `/api/json/builder_contract/*` routes directly.
- Link to generated Ash OpenAPI for resources such as alert rules instead of
  adding retained bespoke examples for routes that are not controller-owned.
- If an API is reference-only or planned, keep it out of these files until it is
  part of the final implementation contract.
