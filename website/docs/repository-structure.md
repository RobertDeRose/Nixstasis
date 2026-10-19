# Project Structure

The repository is split by the thing that gets deployed, so the server, the client, and the gateway can each be
built, tested, and released on their own.

## Root

| Path                                              | Contents                                                                                                                     |
|---------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| `packages/server`                                 | The server, written in Elixir with Phoenix.                                                                                  |
| `packages/client`                                 | The client that runs on each device, written in Go.                                                                          |
| `packages/caddy`                                  | The Caddy image with the AuthCrunch plugin.                                                                                  |
| `packages/frp`                                    | The FRPS image, the pinned FRP download script, and the FRPS config renderer.                                                |
| `packages/shared/e2e_log_viewer`                  | The E2E log viewer shared by the static report export and LiveDashboard.                                                     |
| `deploy/compose`                                  | The supported deployment: the Compose file, Caddyfiles, `frps.toml`, environment templates, and validation scripts.          |
| `website`                                         | The Docusaurus site: `docs/` holds the content, `sidebars.ts` the navigation, and `src/` the styles, fonts, and client code. |
| `scripts`                                         | Repository scripts, such as enabling GitHub Pages deployment.                                                                |
| `.github/workflows`                               | Validation, release, image build, E2E report, and docs workflows.                                                            |
| `mise.toml`, `hk.pkl`, `cog.toml`, `package.json` | Tool versions and tasks, Git hooks and checks, changelog and commit rules.                                                   |
| `flake.nix`                                       | The Nix package for the client.                                                                                              |
| `prod.env`                                        | Production version pins used by release and image workflows.                                                                 |
| `AGENTS.md`                                       | Instructions for automated agents.                                                                                           |

## Server: `packages/server`

| Path                       | Contents                                                                                                                                 |
|----------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| `lib/nixstasis/`           | Context modules such as `devices.ex` and `scripts.ex`, the Ash domain in `domain.ex`, and their resources and helpers in subdirectories. |
| `lib/nixstasis_web/`       | The router, endpoint, controllers, LiveViews, components, channels, plugs, and LiveDashboard pages.                                      |
| `lib/mix/tasks/`           | Custom Mix tasks, such as `db.ensure` and `e2e.export_static`.                                                                           |
| `priv/repo/migrations/`    | Database migrations.                                                                                                                     |
| `priv/static/openapi.yaml` | The generated Ash JSON:API specification.                                                                                                |
| `config/`                  | Compile-time and runtime configuration.                                                                                                  |
| `Dockerfile`, `mise.toml`  | The release image and the pinned Elixir and Erlang versions.                                                                             |

## Client: `packages/client`

| Path                      | Contents                                                                                                                                    |
|---------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| `cmd/nixstasis/`          | The Cobra command tree.                                                                                                                     |
| `internal/`               | `config`, `identity`, `transport`, `telemetry`, `inventory`, `script`, `commands`, `commandpolicy`, `sshauth`, `frp`, `logging`, and `e2e`. |
| `scripts/e2e/`            | The E2E entrypoints, journeys, and scaffolding.                                                                                             |
| `scripts/mock_api/`       | A mock server API for client tests.                                                                                                         |
| `build/`                  | Packaging: the installed file tree with systemd units and templates, plus packaging scripts.                                                |
| `Dockerfile`, `mise.toml` | The device simulator image, and the Go toolchain and client tasks.                                                                          |

Each package's architecture is described in the [Module Reference](modules/index.md).
