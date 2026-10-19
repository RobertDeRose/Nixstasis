# Phoenix UI Polish

The web UI got a consistent, responsive look and feel: a shared page layout, readable screens for dense operational
work, accessible controls, clear feedback, toast notifications, mobile navigation, and saved light, dark, and colour
palette preferences. The original plan is in the [design record](design.md).

## What changed for users

Operators can work through the device, alert, report, script, and policy pages on desktop or phone. Focus, the current
page, loading, errors, and dialogs are always clearly visible.

## How it fits in

Shared layouts and core components define how controls look and behave, instead of each page styling itself. The
theme choice is handled in the browser, while LiveView keeps the state of each workflow on the server.

## Running it

The UI stays usable at narrow widths and when zoomed. Icons and other assets are bundled with the app, so nothing is
loaded from a CDN at runtime.

## Differences from the design

The light and dark toggle grew into a choice of colour palettes, each with light and dark modes.

## Not included

The UI is still Phoenix LiveView; there is no separate frontend application.

## Tests

- `packages/server/test/nixstasis_web/components/core_components_test.exs`: how shared controls render and respond.
- `packages/server/test/nixstasis_web/controllers/layout_test.exs`: the page layout.
- `packages/server/test/nixstasis_web/live/*_live_test.exs`: responsive layouts and dialogs on each page.

## Related pages

- [Server Web](../../modules/server-web.md)
- [Introduction](../../README.mdx)
