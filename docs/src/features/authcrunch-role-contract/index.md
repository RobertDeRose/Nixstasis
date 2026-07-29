# AuthCrunch Role Contract

## Delivery Summary

- Beads feature root: `nixstasis-2ts`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `98d205ed5e93d6d4f37f98dc8be7640eefce737d`
- Design record: `design.md`

## Delivered Capability

Caddy/AuthCrunch maps provider groups into normalized viewer, operator, and admin roles. Phoenix consumes trusted role
claims from the supported Caddy path and maps them to device, report, settings, remote-access, and API capabilities.

## User-Facing Behavior

Viewers receive read-only access, operators can perform day-to-day device and monitoring work, and administrators can
manage privileged settings. Missing, malformed, scoped, and insufficient claims fail closed on protected operations.

## Design Integration

Caddy remains the public authentication edge; Phoenix provides an application authorization backstop. Device API tokens,
E2E enablement, and terminal references remain separate trust mechanisms.

## Operational Impact

Deployments must configure normalized `nixstasis/*` role transforms and claim injection. Local permissive defaults are
limited to direct development and test traffic.

## Reference and Contracts

- [Runtime Boundaries](../../runtime-boundaries.md)
- [Edge Caddy](../../modules/edge-caddy.md)
- [Client-Server Interface](../../client-server-interface.md)

## Validation Evidence

Permission, plug, controller, and LiveView tests cover normalized roles, scoped access, malformed claims, and denied
operations. `packages/server/lib/nixstasis_web/permissions.ex` is the central corroborating implementation.

## Design Reconciliation

### Delivered as Designed

The three normalized roles, Caddy trust boundary, Phoenix capability mapping, and fail-closed behavior were delivered.

### Intentional Changes

Authorization helpers were centralized and subsequently extended for script and command-policy surfaces.

### Deferred Work

Broader multi-tenant RBAC remains outside the current contract.

### Rejected or Removed Scope

The feature did not replace AuthCrunch or merge browser, device, E2E, and terminal credentials.

## Documentation Updated

- `docs/src/runtime-boundaries.md`
- `docs/src/modules/edge-caddy.md`
- `docs/src/client-server-interface.md`
- `deploy/compose/README.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-2ts`. Commit `98d205ed5e93d6d4f37f98dc8be7640eefce737d`
directly closed role-permission gaps in the central Phoenix permission implementation.
