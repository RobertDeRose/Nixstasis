# AuthCrunch Role Contract Design

## Summary

Define the production authorization contract between Caddy/AuthCrunch and the
Phoenix application. The feature documents which AuthCrunch claims or forwarded
headers Phoenix may trust, maps operator roles or groups to Nixstasis
capabilities, and implements the smallest server-side role handling needed to
keep LiveView authorization aligned with the edge policy.

## Source Of Intent

This feature is seeded from `docs/src/planned-features.md` entry
`authcrunch-role-contract`.

## Goals

- Inventory AuthCrunch-related Caddy configuration, Phoenix request handling,
  LiveView session data, and current role/group assumptions.
- Define canonical AuthCrunch-forwarded claims or headers that Phoenix may trust
  after Caddy has authenticated and authorized browser traffic.
- Define operator roles and the capabilities each role grants for dashboard,
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

- `deploy/compose/caddy/Caddyfile` configures an AuthCrunch portal and an
  `entra_policy` that allows `AUTHORIZED_ROLES` and `AUTHORIZED_GROUPS`, verifies
  `JWT_KEY`, validates bearer headers, and injects headers with claims.
- Public browser hosts `nixstasis.<base-domain>`, `frp-admin.<base-domain>`, and
  wildcard device hosts are protected by Caddy `authorize with entra_policy`.
- Phoenix browser routes currently use `NixstasisWeb.Plugs.DevicePermissions`,
  which seeds full device permissions when no session permissions exist.
- `NixstasisWeb.Permissions` already evaluates device and report permission maps,
  including scoped device IDs and report view/manage flags.
- Device runtime APIs continue to authenticate with registration-issued device API
  tokens, not AuthCrunch claims.
- E2E routes continue to be gated by `NixstasisWeb.Plugs.E2EEnabled`, not
  AuthCrunch roles.

## Proposed Contract

### Trust Boundary

Phoenix must trust operator identity and role/group claims only when requests come
through the supported Caddy/AuthCrunch deployment path. Direct Phoenix access in
development may continue to use local defaults, but production docs must not
describe those defaults as authorization.

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
- role claims
- group claims

If AuthCrunch forwards multiple equivalent claim forms, the feature should choose
one canonical Phoenix input and document any accepted aliases explicitly.

### Roles And Capabilities

Define the smallest role set needed by the current product surfaces:

- `viewer`: may view dashboard, devices, alerts, reports, and settings summary
  pages, but may not start remote access or mutate configuration.
- `operator`: may view dashboards, manage devices, start remote access, manage
  alerts, view reports, and use operational workflows that are safe for day-to-day
  operations.
- `admin`: may perform all operator actions plus manage settings and future
  privileged configuration surfaces.

Map AuthCrunch `AUTHORIZED_ROLES` and `AUTHORIZED_GROUPS` to one or more of these
capabilities. The first implementation may use role names only when group-to-role
mapping is not yet available, but it must document that limitation and keep group
authorization at the Caddy edge intact.

If group IDs are accepted by Caddy but Phoenix cannot reliably map them to
capabilities yet, retain group enforcement at the edge and document group-to-role
mapping as intentionally deferred rather than guessing operator-specific group
semantics.

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
- `docs/src/architecture.md`
- `docs/src/modules/edge-caddy.md`
- `docs/src/modules/server-web.md`
- `docs/src/client-server-interface.md`
- `docs/src/reference/contracts.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/operations/secret-rotation.md`
- `docs/src/operations/health-checks.md`
- `docs/src/planned-features.md`

## Code Areas Likely Affected

- `packages/server/lib/nixstasis_web/router.ex`
- `packages/server/lib/nixstasis_web/plugs/device_permissions.ex`
- New or updated Phoenix module for AuthCrunch operator context parsing.
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
- Group-to-role mapping may require operator-specific identity-provider choices;
  the first implementation should document any limits instead of guessing.
