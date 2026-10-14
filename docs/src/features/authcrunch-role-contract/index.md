# AuthCrunch Role Contract

## References

- Beads feature root: `nixstasis-2ts`
- Design record: [design.md](design.md)

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

## Test Coverage

- `packages/server/test/nixstasis_web/permissions_test.exs`: normalized role-to-capability mapping.
- `packages/server/test/nixstasis_web/operator_context_test.exs`: trusted role-claim parsing, scoped access, and
  malformed-claim handling.
- `packages/server/test/nixstasis_web/plugs/device_permissions_test.exs`: plug-level denial of insufficient roles.
- Controller tests under `packages/server/test/nixstasis_web/controllers/` (for example
  `device_scope_json_api_test.exs`, `system_setting_json_api_test.exs`, and `script_json_api_test.exs`): denied
  operations for viewer, operator, and admin claims.
- LiveView tests under `packages/server/test/nixstasis_web/live/`: role-gated UI actions.

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
