# AuthCrunch Role Contract

Caddy and AuthCrunch turn identity-provider groups into three Nixstasis roles: viewer, operator, and admin. Phoenix
reads those roles from Caddy and decides what each one can do with devices, reports, settings, remote access, and the
API. The original plan is in the [design record](design.md).

## What changed for users

- **Viewers** can look but not change anything.
- **Operators** can do the day-to-day device and monitoring work.
- **Admins** can also change privileged settings.

A missing, malformed, or insufficient role, or one carrying a device scope, gets no access to protected actions.

## How it fits in

Caddy is still where people sign in. Phoenix checks permissions again on its side, as a second line of defence. Device
API tokens, the E2E switch and runner credential, and terminal session references are separate mechanisms and are not
affected by roles.

## Running it

Your Caddy configuration must map provider groups to the `nixstasis/*` roles and pass the claims on. The permissive
development defaults only apply to direct development and test traffic.

## Differences from the design

The permission helpers were gathered into one place, and later extended to cover scripts and command policies.

## Not included

- Roles are fleet-wide; there is no multi-tenant role model.
- AuthCrunch is still the sign-in layer, and browser, device, E2E, and terminal credentials stay separate.

## Tests

- `packages/server/test/nixstasis_web/permissions_test.exs`: which capabilities each role gets.
- `packages/server/test/nixstasis_web/operator_context_test.exs`: reading trusted role claims, scoped access, and
  malformed claims.
- `packages/server/test/nixstasis_web/plugs/device_permissions_test.exs`: refusing roles without enough access.
- Controller tests under `packages/server/test/nixstasis_web/controllers/`, such as `device_scope_json_api_test.exs`,
  `system_setting_json_api_test.exs`, and `script_json_api_test.exs`: what viewers, operators, and admins are refused.
- LiveView tests under `packages/server/test/nixstasis_web/live/`: UI actions limited by role.

## Related pages

- [API & Runtime Contracts](../../reference/contracts.md#operator-role-contract)
- [Runtime Boundaries](../../runtime-boundaries.md)
- [Gateway Caddy](../../modules/gateway-caddy.md)
- [Client-Server Interface](../../client-server-interface.md)
