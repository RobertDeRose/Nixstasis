# Phoenix UI Polish

The web UI got a consistent, responsive look and feel: a shared page layout, readable screens for dense operational
work, accessible controls, clear feedback, toast notifications, mobile navigation, and saved light, dark, and colour
palette preferences. The original plan is in the [design record](design.md).

## What changed for users

Operators can work through the device, alert, report, script, and policy pages on desktop or phone. Focus, the current
page, loading, errors, and dialogs are always clearly visible. Tabs, sortable columns, navigation, filters, and theme
controls work from the keyboard and tell assistive technology which item is selected, sorted, current, or pressed.

## How it fits in

Shared layouts and core components define how controls look and behave, instead of each page styling itself. Every
`modal` moves focus inside when it opens, keeps Tab within the dialog, and returns focus to the control that opened it
when it closes. Irreversible deletes ask for confirmation in the shared `confirm_modal` dialog, which opens on Cancel;
reversible actions use the browser's confirm prompt. Device and script tabs share the `Tablist` hook. Pages sit in
`ui-page-shell` under a `header` title, and tables use the shared `table` component, whose sortable columns render
`sort_header` buttons. The device list keeps its own table because its header cell holds the select-all checkbox; it
still uses `sort_header`. The theme choice is handled in the browser, while LiveView keeps the state of each workflow on
the server.

## Running it

The UI stays usable at narrow widths and when zoomed. Icons and other assets are bundled with the app, so nothing is
loaded from a CDN at runtime.

## Differences from the design

The light and dark toggle grew into a choice of eleven colour palettes, offered in the sidebar and in Settings so small
screens without the sidebar can reach them, each with light and dark modes: Coherent Current (the default), nine
alternatives, and High Contrast. Each palette's primary colour matches its name, such as green for Mineral Glass and
blue for Electric Fjord. Every palette meets WCAG AA contrast, and High Contrast targets AAA. Settings adds an optional
highlight colour (teal, deep blue, cyan, green, amber, or magenta) that replaces the palette's primary and accent and
passes AA on every palette; High Contrast ignores it. The palette and highlight lists live in `NixstasisWeb.Theme`, and
each non-default palette or highlight overrides the theme tokens in `assets/css/app.css`. The Noto Sans font is bundled
with the app like the icons.

## Not included

The UI is still Phoenix LiveView; there is no separate frontend application.

## Tests

- `packages/server/test/nixstasis_web/components/core_components_test.exs`: how shared controls render and respond.
- `packages/server/test/nixstasis_web/controllers/layout_test.exs`: the page layout.
- `packages/server/test/nixstasis_web/live/*_live_test.exs`: responsive layouts and dialogs on each page.

## Related pages

- [Server Web](../../modules/server-web.md)
- [Introduction](../../README.mdx)
