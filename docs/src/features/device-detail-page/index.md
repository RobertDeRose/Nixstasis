# Device Detail Page

## Delivery Summary

- Beads feature root: `nixstasis-7ji`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `f47fde36e19b034d3d5805a6f76db3e7917284c7`
- Design record: `design.md`

## Delivered Capability

Operators can open route-backed device details from the filtered Devices workflow and inspect telemetry, PCP metrics,
remote web access, and terminal sessions without restoring obsolete modal APIs.

## User-Facing Behavior

The detail page preserves return context, presents tabbed device information, defaults to PCP monitoring, and provides
clear missing, unauthorized, disconnected, and retry states across desktop and mobile layouts.

## Design Integration

Device detail remains inside the Devices LiveView route and permission boundary. Remote sessions use existing Phoenix
Channels, server SSH process handling, and FRP routing.

## Operational Impact

Operators can diagnose a device and launch bounded remote workflows from one route. Explicit terminal revocation and
session state reduce abandoned access.

## Reference and Contracts

- [Server Devices](../../modules/server-devices.md)
- [Server Web](../../modules/server-web.md)
- [Runtime Boundaries](../../runtime-boundaries.md)

## Validation Evidence

Device LiveView tests cover filtered navigation, authorization, tabs, PCP presentation, terminal lifecycle, and recovery
states. `packages/server/lib/nixstasis_web/live/device_live/show.ex` is direct implementation evidence.

## Design Reconciliation

### Delivered as Designed

Route-backed detail, preserved list context, responsive tabs, authorization, and degraded remote-access states were
delivered.

### Intentional Changes

The final UI made PCP the default tab and moved maximize and fullscreen controls into the tab bar.

### Deferred Work

No obsolete modal API compatibility was retained.

### Rejected or Removed Scope

The feature did not recreate REST modal open and close endpoints.

## Documentation Updated

- `docs/src/modules/server-devices.md`
- `docs/src/modules/server-web.md`
- `docs/src/runtime-boundaries.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-7ji`. Commit `f47fde36e19b034d3d5805a6f76db3e7917284c7`
directly redesigned the detail tabs and established the delivered default view.
