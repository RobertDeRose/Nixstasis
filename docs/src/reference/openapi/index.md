# OpenAPI Contracts

The Ash-generated OpenAPI file at `packages/server/priv/static/openapi.yaml`
documents the Ash JSON:API surface under `/api/json`. The Phoenix controller
APIs used by the Go client, builder UI, TLS approval, and E2E harness are
bespoke routes, so their contracts live here.

## Contracts

- [Device API](device-api.yaml): registration, heartbeat, command results,
  deferred command payloads, device list filtering, and TLS domain approval.
- [Builder API](builder-api.yaml): schema option lookup and builder selection
  validation.
- [E2E API](e2e-api.yaml): E2E run lifecycle, results, logs, cancellation, and
  protocol-version requirements.

## Maintenance Notes

- Keep these contracts aligned with `docs/src/client-server-interface.md` and
  the Phoenix router/controller modules.
- Do not duplicate Ash JSON:API resources here unless a bespoke `/api/v1` or
  `/e2e` controller owns the route.
- If an API is reference-only or planned, keep it out of these files until it is
  part of the final implementation contract.
