# Operational Unknowns

This page records missing, ambiguous, or conflicting operational signals
observable from repository files. It does not prescribe changes.

## Missing Docs

- No single generated OpenAPI document covers Ash JSON:API, `/api/v1`
  controller endpoints, and `/e2e` endpoints. The current contract split is
  explained in [API & Runtime Contracts](reference/contracts.md).

## Ambiguities

- Production AuthCrunch role and claim mapping is future work tracked in
  [Planned Features](planned-features.md), not an unresolved operational unknown.

## Conflicting Signals Between Code and Specs

- Ash JSON:API OpenAPI output covers `/api/json` resources, while the Go client
  uses `/api/v1` controller endpoints. Future API unification is tracked in
  [Planned Features](planned-features.md).

## Areas Where Intent Is Unclear

- Whether the separate production authentication contract for Phoenix-internal
  APIs should be a docs page, a design spec, or generated API documentation.

Traceable references:

- `README.md:341-350`
- `deploy/compose/caddy/Caddyfile:32-38`
