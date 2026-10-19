# Device Detail Page

Each device has its own page, opened from the Devices list, where operators can see its telemetry and PCP metrics,
open its web interface remotely, and start a terminal. The original plan is in the [design record](design.md).

## What changed for users

- Going back from a device returns you to the list as you left it, filters included.
- Device information is split into tabs, opening on PCP monitoring.
- Missing devices, missing permissions, lost connections, and failed sessions each get a clear message and, where it
  makes sense, a retry, on both desktop and mobile.

## How it fits in

The detail page is a route inside the Devices LiveView, so it uses the same permission checks. Remote sessions use the
existing Phoenix Channels, the server's SSH process handling, and FRP routing.

## Running it

Operators can diagnose a device and open a time-limited remote session from one place. Terminals are revoked
explicitly when they end, and their state is tracked, so access is not left open by accident.

## Differences from the design

PCP became the default tab, and the maximize and full-screen controls moved into the tab bar.

## Not included

There are no REST endpoints for opening and closing a device dialog; the page replaced the old dialog entirely.

## Tests

- `packages/server/test/nixstasis_web/live/device_live_test.exs`: navigating from a filtered list, permissions, tabs,
  the PCP view, the terminal lifecycle, and recovery messages.
- `packages/server/test/nixstasis_web/channels/terminal_channel_test.exs`: joining and authorizing the terminal.

## Related pages

- [Server Devices](../../modules/server-devices.md)
- [Server Web](../../modules/server-web.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
