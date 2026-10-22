# Design — Docusaurus Documentation Site

## Metadata

- Feature slug: `docusaurus-docs-site`
- Design path: `website/docs/features/docusaurus-docs-site/design.md`
- Implemented record: `website/docs/features/docusaurus-docs-site/index.md`
- Base branch: `dev`
- Status: delivered

## Feature Summary

Replace the mdBook documentation site with Docusaurus. Content stays in `website/docs`, existing `.md` pages keep plain
CommonMark semantics, and the four OpenAPI specifications render as browsable API reference pages.

## User Intent

The maintainer no longer wants to work within mdBook's limitations and chose Docusaurus over Zensical. The maintainer
chose these constraints during planning:

- Parse `.md` pages as CommonMark, so prose containing Elixir maps (`%{}`), HEEx interpolation, or angle brackets needs
  no escaping. Pages that need React components opt in with the `.mdx` extension.
- Render the OpenAPI specifications as API reference pages as part of this migration.
- Keep content in `website/docs`, so every existing path, cross-link, and guidance reference stays valid.

## Goals

- Every existing page is reachable in the Docusaurus site with the same reading order and grouping.
- Mermaid diagrams render natively, without vendored scripts.
- The Nixstasis brand colors apply in light and dark modes.
- The site has full-text search without an external service.
- `builder-api.yaml`, `device-api.yaml`, `e2e-api.yaml`, and `report-api.yaml` render as operation-level reference pages.
- GitHub Pages deployment and E2E results publishing keep working.
- mise owns the Node toolchain; npm's lockfile owns the site dependencies.

## Non-Goals

- Versioned documentation per release.
- A blog or landing page beyond the existing introduction.
- Rewriting page content beyond what the migration requires.

## User-Facing Behavior

Readers get the same pages under the same grouping, with a collapsible sidebar, local search, light and dark themes,
edit links, and an API reference section generated from the specifications. Contributors run the same
`mise run docs:build` and `mise run docs:serve` commands.

## Requirements

### Functional Requirements

- The docs plugin reads `website/docs` and serves it at the site root path for docs.
- `markdown.format` is `detect`: `.md` files use CommonMark and `.mdx` files use MDX.
- The sidebar mirrors the current `website/docs/SUMMARY.md` hierarchy, including the feature design and implemented feature
  lists.
- Mermaid code fences render through `@docusaurus/theme-mermaid`.
- Broken internal links fail the build.
- OpenAPI pages are generated from the specifications at build time; generation failures fail the build.
- The Pages workflow publishes the built site and copies E2E results to `e2e-results/` in the output.

### Quality Requirements

- `mise run check` stays green, with a docs build step replacing the mdBook build step.
- Site dependencies install from a committed `package-lock.json` with `npm ci`.

### Compatibility and Migration Requirements

- Existing relative Markdown links between pages keep working without edits wherever Docusaurus resolves them.
- Repository paths cited in guidance (`website/docs/...`) stay valid.

## Existing Context

mdBook builds `website/docs` using `docs/book.toml`, a custom `theme/index.hbs`, brand CSS in `theme/nixstasis.css`, and a
forked `mdbook-mermaid` preprocessor with vendored Mermaid scripts and a zoom modal. `website/docs/SUMMARY.md` defines
navigation, including marker-delimited feature lists. hk runs `mdbook build docs` and `mdbook-lint` on documentation
changes. `.github/workflows/docs.yml` builds the book on `main` and after E2E report runs, generates the E2E results page
with `website/scripts/prepare_e2e_results.sh`, and uploads `book/` to Pages.

## Proposed Design

- **Site root:** `website/` follows the standard Docusaurus layout. It holds `package.json`, `package-lock.json`,
  `docusaurus.config.ts`, and `sidebars.ts`; the pages live in `website/docs/`, styles and client code in
  `website/src/`, and static assets in `website/static/`.
- **Navigation:** `sidebars.ts` replaces `SUMMARY.md` as the navigation source, using the same hierarchy.
- **Theme:** brand colors move from mdBook variables to Infima variables in `custom.css`.
- **Search:** `@easyops-cn/docusaurus-search-local` builds an offline index.
- **OpenAPI:** `docusaurus-plugin-openapi-docs` generates MDX pages from the specifications into a generated,
  git-ignored directory; `docusaurus-theme-openapi-docs` renders them.
- **Tooling:** mise tasks run `npm ci` and Docusaurus commands; the mdBook, `mdbook-mermaid`, and `mdbook-lint` tools and
  their configuration are removed.

## Architecture Consistency

### Existing Patterns Reused

- mise tasks are the single entry point for documentation commands.
- hk gates documentation changes on a successful build.
- The Pages workflow structure, gating, and E2E results checkout stay the same.

### Invariants Preserved

- `website/docs` remains the content root.
- Feature records keep durable content only.

### New Decisions Introduced

- Docusaurus is the documentation generator; `sidebars.ts` is the navigation source.
- `.md` is CommonMark; `.mdx` is reserved for pages that need components.

### Architecture Documentation Changes

`website/docs/repository-structure.md` describes the new `website/` layout.

## Operational Considerations

The docs build needs Node from mise and network access for `npm ci`. Pages deployment remains gated by the
`DOCS_DEPLOYMENT_ENABLED` repository variable.

## Documentation Impact

| Documentation concern      | Exact page                                            | Create or update        | Planned change                                       | Owning Beads task |
|----------------------------|-------------------------------------------------------|-------------------------|------------------------------------------------------|-------------------|
| Architecture               | `website/docs/repository-structure.md`                | Update                  | Describe the Docusaurus `website/` layout            | `nixstasis-pdk.5` |
| Development                | `website/docs/development/tooling.md`                 | Update                  | Docs commands, tools, and checks                     | `nixstasis-pdk.5` |
| Development                | `website/docs/development/feature-lifecycle.md`       | Update                  | Register pages in `sidebars.ts`                      | `nixstasis-pdk.5` |
| Development                | `website/docs/features/_template/design.md`           | Update                  | Navigation registration wording                      | `nixstasis-pdk.5` |
| Reference                  | `website/docs/reference/tooling.md`                   | Update                  | Files table and docs workflow                        | `nixstasis-pdk.5` |
| Reference                  | `website/docs/reference/openapi/index.md`             | Update                  | Link the rendered API reference                      | `nixstasis-pdk.3` |
| Navigation                 | `website/sidebars.ts`                                 | Create                  | Replace `website/docs/SUMMARY.md`                    | `nixstasis-pdk.2` |
| Implemented Feature Record | `website/docs/features/docusaurus-docs-site/index.md` | Create during close-out | Delivered capability and deviations from this design | `nixstasis-pdk`   |

## Validation Strategy

- `mise run docs:build` succeeds with broken-link detection set to fail.
- Spot-check rendered pages: a Mermaid diagram, an Elixir-heavy module page, a feature record, and each API spec.
- Light and dark themes show brand colors.
- `mise run check` passes.
- `actionlint` passes on the docs workflow.

## Implementation Decomposition

1. `nixstasis-pdk.1`: this design.
2. `nixstasis-pdk.2`: scaffold the site, sidebar, theme, Mermaid, and search.
3. `nixstasis-pdk.3`: OpenAPI reference pages.
4. `nixstasis-pdk.4`: tooling, hooks, and Pages workflow.
5. `nixstasis-pdk.5`: documentation and guidance updates.

## Dependencies and Parallelism

Tasks 3 and 4 depend on 2 and can proceed in either order; task 5 follows task 4.

## Rollout and Migration

The site switches in one merge. The Pages URL is unchanged; individual page URLs change from `*.html` to clean paths.

## Risks and Tradeoffs

- Some pages may rely on mdBook-specific syntax or HTML that CommonMark parsing in Docusaurus renders differently.
- The Node dependency tree is much larger than mdBook's single binary.
- Old `*.html` page URLs stop resolving.

## Rejected Alternatives

- **Zensical:** closer to plain Markdown, but young, with an incomplete plugin ecosystem and no established OpenAPI
  rendering.
- **MDX for every page:** requires escaping braces and angle brackets across all existing prose.
- **Moving content to `docs/docs`:** invalidates every `website/docs` reference for no reader benefit.

## Open Questions

None.

## Deferred Decisions

- Redirects from old `*.html` URLs.

## Planning Record

### Questions Asked and Answers

- Markdown parsing: CommonMark for `.md`, MDX opt-in.
- OpenAPI rendering: included in this migration.
- Content location: keep `website/docs`.

### Assumptions

- Docusaurus 3.10 with React 19, `docusaurus-plugin-openapi-docs` 5.2, and `@easyops-cn/docusaurus-search-local` 0.55.

### Design Changes During Planning

None. Changes made during implementation are recorded in the [implemented record](index.md).

### Source Material

- `docs/book.toml`, `website/docs/SUMMARY.md`, `docs/theme/`, `.github/workflows/docs.yml`, `hk.pkl`.
