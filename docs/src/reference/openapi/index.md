# OpenAPI Contracts

The Ash-generated OpenAPI specification is served at `/api/json/open_api` and
`/api/json/swaggerui`, and is committed as
`packages/server/priv/static/openapi.yaml`. It documents the generated Ash
JSON:API surface under `/api/json`, including builder actions, alert rules, and
other Ash-backed resources. Regenerate the committed artifact with
`mise x -- mix openapi.generate` from `packages/server`.

The runtime `/api/json/open_api` endpoint is served by
`NixstasisWeb.AshJsonApiRouter`; the static generator uses
`NixstasisWeb.AshJsonApiOpenAPISpec`, which delegates to that same router spec.
Verify that the committed artifact still matches the shared generated spec with:

```bash
mise x -- mix openapi.spec.yaml \
  --check \
  --spec NixstasisWeb.AshJsonApiOpenAPISpec \
  --filename priv/static/openapi.yaml \
  --start-app=false
```

The script-workbench persistence resources remain Ash-owned but are intentionally
excluded from generic JSON:API and this artifact. The current LiveView uses
`Nixstasis.Domain` directly; an audited external contract must be designed before
those records become product API routes.

Phoenix controller APIs used by the Go client, legacy builder compatibility,
Caddy TLS approval, report previews, and the current E2E harness remain bespoke
or compatibility routes. Their wire-compatible controller contracts live here
until a separate migration decision changes ownership.

The device API file documents the current compatibility transport; it remains
aligned with generated Ash coverage and Go-client behavior. The generated
artifact includes all five device-runtime actions. The approved generated target
is the additive
`/api/json/device_runtime/devices` family. Its OpenAPI uses route-level
`deviceApiKey` query security for heartbeat, command results, and payload fetches;
registration is unauthenticated at the application layer and the generated list
uses the operator bearer boundary.

## Contracts

- [Device API](device-api.yaml): registration, heartbeat, command results,
  deferred command payloads, device list filtering, TLS domain approval, and
  the `ssh_authorize`/`ssh_revoke` command payloads delivered by heartbeat.
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
- Keep device compatibility details here because the Go client remains on the
  `/api/v1` wrappers, and verify generated/static OpenAPI coverage after every
  generated-contract change.
- Keep the builder auth/status/body matrix aligned between the generated artifact,
  `builder-api.yaml`, and `client-server-interface.md`.
- Link to generated Ash OpenAPI for resources such as alert rules instead of
  adding retained bespoke examples for routes that are not controller-owned.
- If an API is reference-only or planned, keep it out of these files until it is
  part of the final implementation contract.
