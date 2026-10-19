# Docusaurus Documentation Site

The documentation site is built with Docusaurus instead of mdBook. It has offline full-text search, light and dark
brand themes (Sora for headings, IBM Plex for body text and code), Mermaid diagrams drawn in brand colours that you can
expand and zoom, and an API reference page for every operation in the hand-written OpenAPI specifications. The
original plan is in the [design record](design.md).

## What changed for users

- The sidebar is grouped into Introduction, Architecture, Operations, Development, Reference, and Implemented Features.
  Operations and Implemented Features start collapsed.
- Every diagram has an **Expand** button that opens it in a dialog, with zoom in, zoom out, and reset.
- OpenAPI Contracts has a section each for the Device, E2E, and Report APIs, with one page per operation and
  request samples.
- Linked source files, such as the YAML specifications and packaging scripts, download from the site.
- Published E2E reports are still linked from the E2E Results page.
- Only delivered features are published: a feature's records appear only once its implemented record exists.

## How it fits in

The pages stay in `website/docs`, so every repository path mentioned in guides and feature records still works. `.md`
pages are read as CommonMark; the introduction is the only `.mdx` page, because its logo and wordmark are a component.
Documentation commands still run through mise, and hk still blocks documentation changes that break the build.

## Running it

The Pages workflow builds the site with `mise run docs:build`, copies published E2E reports into
`website/build/e2e-results`, and uploads `website/build`. Page addresses changed from mdBook's `*.html` paths to Docusaurus
routes, under the same Pages base URL.

## Differences from the design

- **Built with Rspack.** The site uses Docusaurus Faster, which bundles with Rspack, because the OpenAPI theme breaks
  webpack's module concatenation, and Rspack is what the plugin's own demo uses. Only the one `v4` setting Faster needs
  is turned on; the full `v4` set would change the CSS order and override the brand theme. Rspack's on-disk
  cache is off, because `docs:serve` and the hk docs build running at the same time corrupt it and crash Rspack.
- **MDX introduction.** The introduction is `README.mdx`, so its logo is bundled with the site; plain HTML images in
  CommonMark pages are not.
- **SVG logo.** The logo is an SVG traced from the original artwork, with gradient shading, kept in
  `website/static/img/` and shared by the navbar, the favicon, and the introduction.
- **Report links.** The E2E Results page links reports with `pathname://`, because the reports are copied in after the
  build and must not be checked as site routes.
- **Flat API sidebars.** The generated OpenAPI sidebars drop the single "untagged" group, since the specifications use
  no tags.
- **Diagram colours.** Brand colours are applied with CSS on top of Mermaid's neutral and dark themes, because
  Mermaid's own theme settings cannot change with light and dark mode. Mermaid measures labels in the site's body font,
  so boxes fit their text.
- **Simpler zoom.** mdBook's zoom window was replaced by a smaller Expand dialog, in `website/src/clientModules/index.ts`.
- **Contributor pages.** Documentation Conventions moved from the Introduction into the Development guide, so the
  Introduction is a single page for new readers.

## Not included

Old mdBook `*.html` addresses do not redirect to the new pages.

## Tests

- `mise run docs:build` regenerates the API pages and fails on any broken link, anchor, or image.
- The hk `docs` step runs that build whenever documentation or site files change, as part of `mise run check`.

## Related pages

- [Developer Tooling](../../development/tooling.md#documentation-site)
- [Documentation Conventions](../../development/documentation-conventions.md)
- [Tooling Reference](../../development/tooling-reference.md)
- [OpenAPI Contracts](../../reference/openapi/index.md)
- [Project Structure](../../repository-structure.md)
- [E2E Results](../../development/e2e/results.md)
