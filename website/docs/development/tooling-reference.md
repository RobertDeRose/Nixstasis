# Tooling Reference

## Files

| File                                | Contract                                                                                                                     |
|-------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| `mise.toml`                         | Declares project tools, environment, and named tasks.                                                                        |
| `mise.lock`                         | Project-owned resolved downloads; commit it.                                                                                 |
| `hk.pkl`                            | Defines the shared check/fix/pre-commit step map.                                                                            |
| `.config/rumdl.toml`                | Configures Markdown linting and deterministic fixes.                                                                         |
| `.editorconfig`                     | Keeps editor output on UTF-8, LF, final newlines, and no trailing spaces.                                                    |
| `_typos.toml`                       | Ignores hash-like identifiers while retaining typo checks elsewhere.                                                         |
| `contextlint.config.json`           | Checks documentation links, anchors, and image targets.                                                                      |
| `cog.toml`                          | Configures Conventional Commits and concise changelogs.                                                                      |
| `.config/cog-changelog.tera`        | Renders plain Markdown changelogs without author noise.                                                                      |
| `scripts/enable-docs-deployment.py` | Configures workflow-built Pages through external `gh`.                                                                       |
| `scripts/serve-pages.py`            | Serves the assembled Pages site locally, resolving paths the way GitHub Pages does.                                          |
| `.github/workflows/validate.yml`    | Runs locked `mise run check` and the test suites on pull requests and releases.                                              |
| `website/docusaurus.config.ts`      | Configures the Docusaurus site, Markdown parsing, Mermaid, search, and OpenAPI generation.                                   |
| `website/sidebars.ts`               | Defines documentation navigation; every durable page is registered here.                                                     |
| `website/package-lock.json`         | Locks the documentation site's npm dependencies; commit it.                                                                  |
| `site/`                             | The product page served at the Pages root, and `brand.css`, the color and font tokens the docs share.                        |
| `.github/workflows/pages.yml`       | Builds the gated Pages site on pushes to `main`, when a successful E2E report run on `main` calls it, or on manual dispatch. |

## Checks

`mise run check` runs these hk steps; `mise run fix` applies the fixes for the steps that have one. Each step runs only
when matching files change.

| Area               | Steps                                                                                                                                                                                   |
|--------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Repository hygiene | Byte-order marks, case conflicts, executable shebangs, symlinks, large files, merge conflicts, private keys, mixed line endings, trailing whitespace, final newlines, and smart quotes. |
| Tooling            | `mise` config formatting.                                                                                                                                                               |
| Markdown and docs  | `rumdl`, `markdown-table-formatter`, `contextlint` for links, anchors, and images, `typos`, and `docs`, which builds the site.                                                          |
| Deployment         | `compose-stack` and `frps-render`; see [Local Stack](local-stack.md#contract-validation).                                                                                               |
| Server             | `server-compile` with warnings as errors, `server-deps` for unused lock entries, and `server-format`.                                                                                   |
| Client             | `go-fmt` (`gofumpt`, then `goimports` with local import grouping), `go-mod` for module tidiness, and `go-lint`.                                                                         |
| Commit messages    | Cocogitto, Conventional Commit format, line lengths, required scopes, and the `Beads:` footer.                                                                                          |

Custom steps exist only where hk has no equivalent built-in, and independent steps run in parallel without ordering
constraints.

## Container build caches

The server and Caddy image workflows use BuildKit's GitHub Actions cache backend
(API v2) to reuse unchanged layers across fresh hosted runners. The existing
Docker actions provide cache access without new registry credentials or secrets.
Cache exports use `mode=max` to include intermediate dependency and compilation
layers, with distinct scopes so the three build targets do not overwrite one
another:

- `.github/workflows/build_server_image.yml`: `server-image`.
- `.github/workflows/build_caddy_image.yml`: `caddy-proxy-test` for the exported
  proxy-test binary and `caddy-image` for the final image.

Cache availability follows GitHub's branch-access rules and eviction policy; the
first build or a cache miss still needs a normal build. Exports use
`ignore-error=true` so a read-only cache or failed cache upload does not turn a
successful image build into a failure. Missing cache entries are rebuilt.

Caching does not eliminate base-image metadata requests or the BuildKit bootstrap
image pull during builder setup. Docker Hub timeouts and pull-rate limits can
still fail those pulls. No Docker Hub login is configured by these workflows.
GHCR publication happens only when the Release workflow calls them with a
version, or from a manual dispatch with `push` enabled; see
[Releasing](releasing.md). See
[Docker's cache guidance](https://docs.docker.com/build/ci/github-actions/cache/).

## Commit messages and changelogs

Changelog-visible `feat`, `fix`, `perf`, and `refactor` commits require a scope. The commit hook also checks Conventional
Commit syntax, a 72-character subject, 100-character body lines, and an optional canonical `Beads:` footer; the Beads,
length, and scope checks skip Git comments and stop before scissors or diff sections. `cog changelog` omits internal
build, chore, CI, documentation, release, style, and test commits, and renders breaking changes as plain Markdown.

`cog.toml` accepts any syntactically valid scope. To constrain scopes, add a `scopes = ["..."]` allowlist, document each
subsystem here, update `AGENTS.md` to match, and run `cog check`.

## Tasks

| Task                                                                                                                                  | Defined in                       | Behavior                                                                                                                 |
|---------------------------------------------------------------------------------------------------------------------------------------|----------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| `check`                                                                                                                               | root                             | Run every hk check without fixing.                                                                                       |
| `fix`                                                                                                                                 | root                             | Apply deterministic hk fixes.                                                                                            |
| `lock`                                                                                                                                | root                             | Regenerate every `mise.lock`; `--bump` upgrades to the latest versions.                                                  |
| `docs:install`                                                                                                                        | root                             | Install site dependencies with `npm ci` when the npm lock changes.                                                       |
| `docs:build`                                                                                                                          | root                             | Build the site into `website/build`.                                                                                     |
| `docs:serve`                                                                                                                          | root                             | Serve the site with hot reload on port 3000 or a supplied port.                                                          |
| `site:build`                                                                                                                          | root                             | Build the docs and assemble the Pages site into `_site/nixstasis`: the product page at the root, the docs under `docs/`. |
| `site:serve`                                                                                                                          | root                             | Build the Pages site and serve it at `http://127.0.0.1:3000/nixstasis/` or a supplied port.                              |
| `docs:deployment:enable`                                                                                                              | root                             | Configure GitHub Pages and enable its deployment gate through `gh`.                                                      |
| `deploy:dev`                                                                                                                          | `.mise/tasks/deploy/dev.sh`      | Manage the local Compose stack; see [Local Stack](local-stack.md).                                                       |
| `deploy:dev:seed`                                                                                                                     | `.mise/tasks/deploy/dev/seed.sh` | Seed fixture data into the local stack's database.                                                                       |
| `test`, `test:coverage`                                                                                                               | `packages/client`                | Run Go tests with the race detector and coverage; print the coverage summary.                                            |
| `test:packaging`                                                                                                                      | `packages/client`                | Verify the native SSH packaging contracts; requires Linux and GNU `stat`.                                                |
| `build`, `build:local`, `clean`                                                                                                       | `packages/client`                | Build the client binary, run the CLI locally, remove build artifacts.                                                    |
| `release:check`, `release:snapshot`, `release:snapshot:archives`, `release:snapshot:native`, `release:snapshot:run`, `release:verify` | `packages/client`                | Validate GoReleaser configuration, build snapshot artifacts, and verify release artifacts.                               |
| `mock-api`                                                                                                                            | `packages/client`                | Run the mock server API.                                                                                                 |
| `e2e:scaffold`                                                                                                                        | `packages/client`                | Generate an E2E journey scaffold.                                                                                        |

## Platforms and environment

Linux is the supported runtime, release, and packaging-validation platform. The tool locks cover `linux-x64`,
`linux-arm64`, and `macos-arm64`; Intel macOS is not locked, and macOS downloads do not establish macOS product or
packaging support.

The mise environment routes Git hooks through mise with `HK_MISE=1` and sets `GIT_CONFIG_PARAMETERS="'merge.ff=only'"`,
so Git rejects merges that would need a merge commit. `gh` is an external prerequisite for administrative tasks, not a
mise tool. Pages deployment triggers and permissions are described in
[GitHub Pages Deployment](github-pages.md).
