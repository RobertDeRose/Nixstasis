<!-- workflow-migration:legacy-markdown-to-beads -->

# AuthCrunch Role Contract Design

## Summary

Define the production authorization contract between Caddy/AuthCrunch and the
Phoenix application. The feature documents which AuthCrunch claims or forwarded
headers Phoenix may trust, maps provider-specific OIDC groups to normalized
Nixstasis roles in Caddy/AuthCrunch, and implements the smallest server-side role
handling needed to keep LiveView authorization aligned with the edge policy.

## Source Of Intent

This feature is seeded from `docs/src/planned-features.md` entry
`authcrunch-role-contract`.

## Goals

- Inventory AuthCrunch-related Caddy configuration, Phoenix request handling,
  LiveView session data, and current role/group assumptions.
- Define canonical AuthCrunch-forwarded claims or headers that Phoenix may trust
  after Caddy has authenticated and authorized browser traffic.
- Define normalized operator roles and the capabilities each role grants for dashboard,
  devices, remote access, alerts, reports, settings, and E2E surfaces.
- Document behavior for missing, malformed, or insufficient role claims.
- Decide and implement where role-aware UI behavior belongs in Phoenix, reusing
  existing permission helpers when practical.
- Update deployment and operations docs so operators know which AuthCrunch roles
  or groups must be configured.

## Non-Goals

- Replacing AuthCrunch as the browser authentication and authorization edge.
- Changing the device runtime API authentication contract.
- Treating device API tokens, E2E enablement, or terminal session refs as
  substitutes for browser/operator authorization.
- Removing Caddy's existing `authorize with entra_policy` checks from protected
  production hosts.
- Implementing full multi-tenant RBAC beyond the roles required by current
  operator surfaces.
- Changing Caddy's public ingress topology or production TLS behavior.

## Current Behavior

- `deploy/compose/caddy/Caddyfile` configures an AuthCrunch portal, transforms
  provider-specific OIDC groups into `nixstasis/*` roles, and applies an
  `entra_policy` that allows `AUTHORIZED_ROLES` and `AUTHORIZED_GROUPS`, verifies
  `JWT_KEY`, validates bearer headers, and injects headers with claims.
- Public browser hosts `nixstasis.<base-domain>`, `frp-admin.<base-domain>`, and
  wildcard device hosts are protected by Caddy `authorize with entra_policy`,
  except for the Go client device protocol routes on `nixstasis.<base-domain>`.
  Those device protocol routes bypass AuthCrunch at Caddy and authenticate in
  Phoenix with registration-issued device credentials where applicable.
- Phoenix browser routes use `NixstasisWeb.Plugs.DevicePermissions`, which maps
  trusted AuthCrunch roles into browser permission session state and keeps
  local-development permissive defaults for direct dev/test requests without
  AuthCrunch claim headers.
- `NixstasisWeb.Permissions` already evaluates device and report permission maps,
  including scoped device IDs and report view/manage flags.
- Device runtime APIs continue to authenticate with registration-issued device API
  tokens, not AuthCrunch claims.
- E2E routes continue to be gated by `NixstasisWeb.Plugs.E2EEnabled`, not
  AuthCrunch roles.

## Proposed Contract

### Trust Boundary

Phoenix must trust operator identity and role claims only when requests come
through the supported Caddy/AuthCrunch deployment path. Direct Phoenix access in
development may continue to use local defaults, but production docs must not
describe those defaults as authorization or expose direct Phoenix access as a
supported production browser path.

Caddy remains the production browser authentication and authorization edge.
Phoenix role handling is an application-level capability mapper for LiveView and
channel behavior after Caddy has admitted the request; it must not be documented
as a replacement for Caddy `authorize with entra_policy`.

### Claim Inputs

The implementation must inventory the actual headers Caddy/AuthCrunch forwards
when `inject headers with claims` is enabled. The final contract should name the
canonical header keys for:

- operator subject or user identifier
- display name or email, if available
- normalized role claims from `X-Token-User-Roles`

Provider-specific OIDC group claims are consumed by Caddy/AuthCrunch transforms,
not by Phoenix. Phoenix should consume `X-Token-User-Roles` only after Caddy has
mapped groups to normalized `nixstasis/*` roles.

### Roles And Capabilities

Define the smallest role set needed by the current product surfaces:

- `nixstasis/viewer`: may view dashboard, devices, alerts, reports, and settings summary
  pages, but may not start remote access or mutate configuration.
- `nixstasis/operator`: may view dashboards, manage devices, start remote access, manage
  alerts, view reports, and use operational workflows that are safe for day-to-day
  operations.
- `nixstasis/admin`: may perform all operator actions plus manage settings and future
  privileged configuration surfaces.

Map provider-specific OIDC groups to one or more of these capabilities in
Caddy/AuthCrunch, not Phoenix. Caddy `transform user` blocks should convert
operator-provided group values into provider-generic `nixstasis/viewer`,
`nixstasis/operator`, and `nixstasis/admin` roles before the request is proxied.
Phoenix should consume only those normalized roles from `X-Token-User-Roles`.

### Phoenix Authorization Shape

Prefer a small Phoenix authorization boundary over scattered LiveView conditionals:

- Parse and normalize trusted AuthCrunch claims in a plug or module used by the
  browser pipeline.
- Store normalized operator context and permission maps in the session or assigns
  consumed by LiveViews.
- Reuse `NixstasisWeb.Permissions` for device and report capability checks where
  possible.
- Keep terminal session authorization tied to server-issued terminal session refs
  and device permission checks.
- Treat `/api/json` as an operator/developer resource API rather than a device
  runtime protocol. Caddy/AuthCrunch protects it on the public host, and Phoenix
  applies route-level JSON:API role checks as a fail-closed backstop.

### Failure Behavior

- Missing role/group claims in production should deny privileged UI behavior and
  should not silently grant full permissions.
- Malformed claim headers should fail closed, log enough context for operators,
  and avoid logging raw tokens or full sensitive claim blobs.
- Insufficient roles should show existing unauthorized LiveView behavior where
  possible instead of exposing data and hiding only buttons.
- Local development may retain permissive defaults only when the request is not
  using the production AuthCrunch claim path and docs mark the behavior as local
  development only.

## Docs And Pages Likely Affected

- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/.env.example`
- `deploy/compose/README.md`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `deploy/compose/scripts/validate_stack.sh`
- `docs/src/architecture.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/modules/edge-caddy.md`
- `docs/src/modules/server-web.md`
- `docs/src/client-server-interface.md`
- `docs/src/reference/contracts.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/operations/secret-rotation.md`
- `docs/src/operations/health-checks.md`
- `docs/src/planned-features.md`

## Code Areas Likely Affected

- `packages/server/lib/nixstasis_web/plugs/device_permissions.ex`
- `packages/server/lib/nixstasis_web/operator_context.ex`
- `packages/server/lib/nixstasis_web/permissions.ex`
- `packages/server/lib/nixstasis_web/live/**/*`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex`
- `packages/server/test/nixstasis_web/**/*`
- `deploy/compose/scripts/validate_stack.sh`

## Validation

- Add tests for claim parsing and role-to-capability mapping.
- Add request or LiveView tests for allowed and denied role scenarios for device
  detail, remote access, reports, alerts, and settings where implemented.
- Add tests proving malformed or missing production AuthCrunch claims do not grant
  privileged permissions.
- Confirm direct device runtime API auth remains unchanged.
- Run `deploy/compose/scripts/check_runtime_contract.sh` if Compose AuthCrunch
  contract inputs or Caddy behavior change.
- Run `deploy/compose/scripts/validate_stack.sh deploy/compose/.env.example` when
  Compose validation changes and Docker is available; otherwise document why it is
  not runnable.
- Run `mix precommit` from `packages/server` after server changes.
- Run `mdbook build docs` after docs updates.
- Run `hk check -a` before feature close-out.

## Reconciliation Bookends

- Before implementation, inventory AuthCrunch headers and current permission
  consumers before deciding final role names or claim parser behavior.
- If repository evidence is insufficient to identify AuthCrunch claim headers,
  consult AuthCrunch/Caddy security documentation and record the resulting source
  of truth in the feature docs.
- Update Caddy/deployment docs and Phoenix authorization behavior in the same
  implementation unit when the final contract is known.
- Before completion, search for `AUTHORIZED_ROLES`, `AUTHORIZED_GROUPS`,
  `AuthCrunch`, `device_permissions`, and `report_permissions` across docs and
  server code to ensure the final contract is described consistently.
- Keep production authorization docs separate from local development shortcuts.

## Risks And Tradeoffs

- Caddy/AuthCrunch may authorize access at the edge while Phoenix still needs
  role-aware UI behavior; duplicating policy can drift unless the contract is
  explicit.
- Over-modeling RBAC too early can add complexity before operator needs are
  proven.
- Trusting forwarded headers is only safe behind the supported Caddy deployment;
  direct Phoenix exposure must not become a production path.
- Group-to-role mapping requires operator-specific identity-provider group values,
  but Caddy owns that mapping so Phoenix remains provider-agnostic.
