# Known Gaps & Unknowns

This page records missing, ambiguous, or conflicting signals observable from repository files. It does not prescribe changes.

## Missing Specs

- No spec directory `006` is present in `specs`.
- No dedicated architecture spec exists for AuthCrunch claim mapping beyond README notes.
- No dedicated production authentication contract for Phoenix-internal APIs is present beyond Caddy/AuthCrunch deployment configuration.
- No single OpenAPI document covers both `/api/v1` controller endpoints and `/e2e` endpoints in `packages/server/priv/static/openapi.yaml`; that file is generated for Ash JSON:API.

## Ambiguities

- README describes AuthCrunch group transforms as future follow-up work; current Caddyfile authorization policy allows roles `*`.

## Conflicting Signals Between Code and Specs

- Ash JSON:API OpenAPI output covers `/api/json` resources, while the Go client uses `/api/v1` controller endpoints.

## Areas Where Intent Is Unclear

- Whether the LiveView UI should consume AuthCrunch-injected headers for role-aware behavior; README states this is future work.
- Whether the separate production authentication contract for Phoenix-internal APIs should be a docs page, a spec, or generated API documentation.

Traceable references:

- `README.md:341-350`
- `deploy/compose/caddy/Caddyfile:32-38`
