# Dashboard Home

The home page gives operators a picture of the fleet at a glance: total devices, how many are online, approvals
waiting, and active alerts, each linking straight to the page where you deal with it. The original plan is in the
[design record](design.md).

## What changed for users

- Each summary card is clickable and takes you to the matching workflow.
- The counts update by themselves as devices register, send heartbeats, get approved or deleted, and as alerts fire.
- An empty fleet, or a partial outage, shows a clear message rather than a blank or broken page.

## How it fits in

The dashboard reads from the existing server contexts and listens for LiveView PubSub updates, so it never keeps its
own copy of device state. Online and offline counts use the same heartbeat rules as everywhere else. Device totals are
calculated as the signed-in operator, so someone limited to some devices only sees totals for those, and an invalid
scope shows nothing.

## Running it

Updates are batched briefly, so a burst of heartbeats does not make the page refresh constantly, while the numbers stay
current.

## Differences from the design

Later work added that batching, explicit notifications when a device is deleted, selectable colour palettes, and
per-operator device totals. None of it changed what the dashboard is for.

## Not included

The dashboard has no separate analytics store and no connectivity model of its own.

## Tests

- `packages/server/test/nixstasis_web/live/dashboard_live_test.exs`: counts from seeded data, navigation, an empty
  fleet, PubSub updates, unknown messages, and keeping filters and counts separate.
- `packages/server/test/nixstasis/devices/stats_test.exs`: the device totals.

## Related pages

- [Introduction](../../README.mdx)
- [Server Web](../../modules/server-web.md)
- [Server Monitoring](../../modules/server-monitoring.md)
