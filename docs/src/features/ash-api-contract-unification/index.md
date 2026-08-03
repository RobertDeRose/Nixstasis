# Ash API Contract Unification

## Delivery Summary

- Beads feature root: `nixstasis-zf5`
- Status: implemented and reconciled; delivery action pending
- Pull request: not created; no PR action selected
- Merge commit: not merged; fast-forward delivery remains available
- Design record: [design.md](design.md)

## Delivered Capability

Nixstasis now uses Ash-backed actions and generated OpenAPI for the externally
consumed API contracts covered by this feature. Builder actions remain available
through generated `/api/json/builder_contract/*` routes, and the device runtime
has an additive generated route family under
`/api/json/device_runtime/devices` for listing, registration, heartbeat,
command-result acknowledgement, and deferred command-payload retrieval.

The existing Go client remains on the compatible `/api/v1` transport. Generated
routes share the same domain orchestration and preserve device authentication,
status codes, response shapes, rate limits, telemetry, command delivery,
replay, and payload behavior without requiring an unversioned client migration.

## User-Facing Behavior

- API consumers can discover builder and device-runtime action schemas in the
  committed Ash-generated OpenAPI artifact.
- Operators can use the generated device list with the existing device filters
  and operator/device-view authorization boundary.
- Devices can use the additive generated registration, heartbeat, command-result,
  and payload actions with the documented `deviceApiKey` query scheme.
- Registration remains a public credential-issuance action; heartbeat,
  command-result, and payload routes authenticate the device API key and retain
  unknown-device, missing/invalid-key, and unapproved-device error precedence.
- Existing `/api/v1` clients continue to receive their established JSON
  envelopes and statuses, including `201` registration, `200` heartbeat and
  payload fetch, `202` command results, and legacy error behavior.
- Caddy TLS approval, E2E workflow routes, and development TLS diagnostics
  remain controller-owned. Report preview remains deferred until an external
  export contract is approved. Script-workbench persistence resources remain
  internal Ash resources without generic CRUD routes.

## Design Integration

Ash owns durable resource/action contracts where generated OpenAPI provides a
concrete benefit. Domain-specific actions delegate to `Nixstasis.Devices`,
`Nixstasis.Monitoring`, `Nixstasis.Scripts`, and command-policy orchestration;
controllers remain thin compatibility adapters rather than duplicating workflow
logic.

The generated device-runtime family is deliberately separate from operator CRUD
at `/api/json/devices`. `JsonApiPermissions` owns route-specific device lookup,
API-key authentication, actor assignment, and operator authorization. The raw
API key is not an Ash action argument. The compatibility transport remains the
Go client's boundary until a separately reviewed client migration.

## Operational Impact

No deployment migration, client upgrade, or new configuration is required for
the additive generated routes. Operators and integrators should use the
committed generated OpenAPI for new Ash consumers and retain the bespoke
compatibility references when an existing client requires `/api/v1` envelopes
or statuses.

Generated heartbeat and other device-runtime routes use the existing rate-limit
categories. Inventory remains untrusted evidence, command policy remains
server-owned, and command payload fetching has no acknowledgement side effect.

## Reference and Contracts

- [Client-Server Interface](../../client-server-interface.md)
- [API & Runtime Contracts](../../reference/contracts.md)
- [OpenAPI Contracts](../../reference/openapi/index.md)
- [Architecture Overview](../../architecture.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
- [Server Web](../../modules/server-web.md)
- [Server Devices](../../modules/server-devices.md)
- [Server E2E](../../modules/server-e2e.md)
- [Server Reporting](../../modules/server-reporting.md)
- [Deployment Compose](../../modules/deployment-compose.md)

The generated canonical artifact is
`packages/server/priv/static/openapi.yaml`. Bespoke
[Device API](../../reference/openapi/device-api.yaml) and
[Builder API](../../reference/openapi/builder-api.yaml) references remain the
compatibility contracts for retained `/api/v1` wrappers; report and E2E
contracts remain bespoke by design. The internal `endpoint-inventory.md` and
`contract-design.md` files preserve the implementation audit record but are not
separate published navigation pages.

## Validation Evidence

- Final server precommit: 576 tests, 0 failures.
- Focused device-runtime, compatibility, and OpenAPI contract tests: 49 tests,
  0 failures.
- Go transport compatibility tests passed with
  `mise x -- go test ./internal/transport`.
- `mix ash.codegen --check`, generated OpenAPI regeneration, and static OpenAPI
  equality checks passed.
- `uv run scripts/check-docs.py` passed with 0 errors and 16 known legacy
  warnings; `mdbook build docs`, focused Rumdl, YAML parsing, and
  `git diff --check` passed.
- Repository-wide `mise run check` remains limited by unavailable isolated
  worktree Mix dependencies and unrelated repository Markdown/table/
  formatter/typos debt. The untouched full client suite retains the known
  slow-script warning test failure.

## Design Reconciliation

### Delivered as Designed

- Every inventoried non-UI endpoint has an explicit Ash-backed,
  retained-controller, UI-only, or deferred classification.
- Builder contracts and the five approved device-runtime actions use
  domain-specific Ash boundaries and generated OpenAPI.
- `/api/v1` compatibility wrappers preserve the Go-client wire and
  authentication contract while generated routes are additive.
- Caddy, E2E, diagnostics, report preview, and script-workbench boundaries
  remain retained, deferred, or UI-only as designed.

### Intentional Changes

- The generated device-runtime surface is additive rather than a replacement
  for `/api/v1`; Go-client transport migration is explicitly deferred for a
  separate compatibility review.
- Generated generic-action routes use JSON:API transport and route-specific
  security/status documentation, while compatibility wrappers retain their
  plain JSON shapes and legacy statuses.
- The six script-workbench resources remain Ash-owned but have no generic
  JSON:API routes because CRUD would bypass workflow validation and audit
  boundaries.

### Deferred Work

- Migrate the Go client to generated device-runtime routes after a separately
  reviewed compatibility plan.
- Decide whether report export, E2E generated contracts, or development
  diagnostics warrant future Ash/API work.
- Design audited domain-specific script-workbench actions if an external
  consumer requires that surface.

### Rejected or Removed Scope

- Converting browser LiveView routes, Caddy's TLS ask endpoint, or the current
  E2E workflow into Ash solely for architectural uniformity.
- Replacing Ash-generated OpenAPI with a second generator.
- Adding package installation or client-side authorization based on untrusted
  command inventory.

## Documentation Updated

- `docs/src/features/ash-api-contract-unification/index.md`
- `docs/src/features/ash-api-contract-unification/design.md`
- `docs/src/features/ash-api-contract-unification/contract-design.md`
- `docs/src/features/ash-api-contract-unification/endpoint-inventory.md`
- `docs/src/SUMMARY.md`
- `docs/src/features/index.md`
- `docs/src/planned-features.md`
- `docs/src/architecture.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/client-server-interface.md`
- `docs/src/modules/server-devices.md`
- `docs/src/modules/server-web.md`
- `docs/src/reference/contracts.md`
- `docs/src/reference/openapi/index.md`
- `docs/src/reference/openapi/device-api.yaml`
- `docs/src/reference/openapi/builder-api.yaml`
- `docs/src/features/server-stary-script-workbench/design.md`
- `packages/server/priv/static/openapi.yaml`

Existing E2E, reporting, and Compose pages were reviewed and retain their
route-specific boundaries without requiring semantic changes.

## Audit Trail

The reviewed design and execution graph were committed in `c0e2cd8`. Builder
and generated-resource reconciliation followed in `a633fa7` and `82e594b`.
Device contract design and implementation were delivered through
`5d555e1`, `4a431bc`, `46c4d43`, and `6eec2c4`.

The implementation coordinator `nixstasis-zf5.7` closed after required children
`.7.37` through `.7.42` passed acceptance. Child review artifacts and final
implementation follow-up evidence are recorded in Beads and `/tmp` review
artifacts. Close-out documentation and holistic delivery/drift reviews are
recorded on `nixstasis-zf5.8` through `nixstasis-zf5.12`; delivery remains a
separate explicit action.
