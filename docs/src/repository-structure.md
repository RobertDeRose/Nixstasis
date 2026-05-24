# Repository Structure

## Root

- `README.md`: project overview, architecture notes, E2E harness documentation, and FRP/Caddy/AuthCrunch context.
- `AGENTS.md`: repository instructions for automated agents.
- `package.json`, `hk.pkl`, `.pre-commit-config.yaml`: repository-level commit and hook tooling.
- `mise.toml`: repository-wide tool version/configuration entry point that
  discovers package-local mise configs.
- `prod.env`: shared production version pins referenced by release/deployment workflows.
- `book.toml`: mdBook configuration.
- `docs/src`: mdBook documentation source tree.
- `book/`: generated mdBook output.

## Server: `packages/server`

- Language: Elixir.
- Framework/runtime: Phoenix, Phoenix LiveView, Ash, Ecto/PostgreSQL, OTP.
- Major paths:
  - `lib/nixstasis/application.ex`: OTP application supervision tree.
  - `lib/nixstasis/domain.ex`: Ash domain and JSON:API resource routing.
  - `lib/nixstasis/*.ex`: context modules for devices, monitoring, reporting, dashboard, settings, alerts, E2E, deployment utilities.
  - `lib/nixstasis/*/*.ex`: Ash resources, support modules, GenServers, SSH and schema utilities.
  - `lib/nixstasis_web/router.ex`: Phoenix route definitions.
  - `lib/nixstasis_web/controllers`: JSON controllers.
  - `lib/nixstasis_web/live`: LiveView modules and LiveComponents.
  - `lib/nixstasis_web/channels`: Phoenix Channels for terminal sessions.
  - `lib/nixstasis_web/components`: function components and layouts.
  - `lib/nixstasis_web/live_dashboard`: LiveDashboard E2E pages and hooks.
  - `priv/repo/migrations`: database migrations.
  - `priv/static/openapi.yaml`: generated Ash JSON:API OpenAPI output.
  - `config/*.exs`: compile-time and runtime configuration.
  - `mise.toml`: server-local Elixir and Erlang tool versions.
  - `Dockerfile`: server OCI image build.

## Client: `packages/client`

- Language: Go.
- Runtime: compiled CLI/service-style binary with Starlark execution and FRPC process management.
- Major paths:
  - `cmd/nixstasis`: Cobra CLI commands.
  - `internal/config`: config loading and default paths.
  - `internal/identity`: local device identity detection and stored runtime credentials.
  - `internal/transport`: HTTP client for Phoenix `/api/v1` device endpoints.
  - `internal/telemetry`: telemetry payload types.
  - `internal/script`: Stary/Starlark parsing, validation, execution, builtins, reports, and REPL support.
  - `internal/commands`: server-issued command execution.
  - `internal/frp`: FRPC lifecycle and config rendering.
  - `internal/e2e`: E2E runner, journey executor, selector, API client, and runtime scripts.
  - `scripts/e2e`: E2E shell entrypoints, config, journey specs, and scaffolding.
  - `scripts/mock_api`: mock API used by client workflows/tests.
  - `build/root-dir`: package filesystem assets, including systemd units and config templates.
  - `mise.toml`: client-local Go toolchain, Go tooling, and client tasks.

## Infrastructure and Edge

- `deploy/compose`:
  - Supported server deployment path.
  - Defines Compose services for `nixstasis`, `caddy`, `frps`, and optional `postgres`.
  - Includes runtime contract validation and Compose rendering scripts.
- `packages/caddy`:
  - Caddy Dockerfile and build script for Caddy with the AuthCrunch plugin.
- `packages/frp`:
  - FRP image/package build assets and Dockerfile.
- `packages/shared/e2e_log_viewer`:
  - Shared static E2E log viewer assets.

## Features and Workflows

- `docs/src/features`: docs-driven feature designs and task history.
- `.github/workflows`: build, release, E2E Pages, and config-check workflows.

## Separation of Concerns

- Server code is isolated under `packages/server`.
- Client code is isolated under `packages/client`.
- Infrastructure and deployment configuration is isolated under `deploy/compose`, `packages/caddy`, and `packages/frp`.
- Cross-cutting feature docs and repository automation live under `docs/src/features` and `.github`.
