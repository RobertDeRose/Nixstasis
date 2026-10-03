# Nixstasis Server (Elixir/Phoenix)

The server application is the Phoenix + LiveView control plane for the Nixstasis
deployment. The supported production path for this feature is the Compose stack
under `deploy/compose`.

## Features

- LiveView UI for fleet health, approvals, alerts, and reports.
- JSONB-backed device and telemetry storage (Postgres).
- API endpoints for device registration and heartbeat polling.
- Schema-driven dropdown APIs for alert/report builders. Generated Ash JSON:API
  contracts are available under `/api/json/builder_contract/*`; legacy JSON
  compatibility wrappers remain under `/api/v1`:
  - `GET /api/v1/builder-schemas`
  - `GET /api/v1/builder-schemas/:schema_id/versions/:schema_version/options`
  - `POST /api/v1/builder-configurations/validate`
- Integrates with Caddy/AuthCrunch and FRP for secure remote access.

## Local development

- Elixir `~> 1.19`
- Erlang/OTP (compatible with Elixir 1.19)
- Postgres, Apple Container, Docker, or Podman

## Setup

```bash
mix setup
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

If nothing is already listening on the configured local Postgres port, DB-backed
Mix tasks such as `mix phx.server`, `mix test`, `mix ash.setup`, and common Ecto
tasks will try to start a local `postgres:16-alpine` container automatically by
using `container`, `docker`, or finally `podman`.

`mix phx.server` also runs `mix ecto.migrate`, which ensures the database is
available and applies pending migrations before Phoenix boots.

The underlying helper task is `mix db.ensure`.

- Disable auto-start with `NIXSTASIS_DB_AUTOSTART=false`.
- Override the container name with `NIXSTASIS_DB_CONTAINER`.
- Override the image with `NIXSTASIS_DB_IMAGE`.

## Supported Deployment

- Build the runtime image with `docker build -f packages/server/Dockerfile -t nixstasis-server:test packages`.
- Run the supported stack from `deploy/compose`.
- Run migrations explicitly with `bin/migrate` inside the release container.
- The abandoned Debian packaging path is not part of the supported deployment
  surface for this feature.

For Compose dev-harness remote-access validation, use the local-only Compose
helpers under `deploy/compose/scripts`. Dev-harness mode keeps browser access
through Caddy, publishes Phoenix on loopback only for token-protected diagnostics,
and uses Caddy internal certificates instead of public ACME issuance.

### LiveDebugger (optional)

LiveDebugger is disabled by default to keep dev startup fast and is excluded from
warning-as-error server compilation unless explicitly enabled.

Enable it only when needed:

```bash
LIVE_DEBUGGER=true mix deps.get
LIVE_DEBUGGER=true mix phx.server
```

## Tests

```bash
mix test
```

## Ash codegen workflow

When you change Ash resources, treat `mix ash.codegen --dev` output as temporary
local iteration state.

- Use `mix ash.codegen --dev` only while actively iterating on resource changes.
- Before committing, run `mix ash.codegen <descriptive_name>` to replace any
  dev-only migrations and snapshots with production-ready files.
- Commit the named migration and named snapshots.
- Do not commit `*_dev.exs` migrations or `*_dev.json` resource snapshots.
- Use `mix ash.codegen --check` to verify the repo has no pending codegen work.

If you previously applied now-replaced dev migrations locally, reset or rebuild
your local database before continuing.

## Configuration

- Runtime config: `config/runtime.exs`
- App config: `config/config.exs`
- Database config: `config/dev.exs`, `config/test.exs`
- Canonical runtime inputs for supported deployments:
  `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, `BASE_DOMAIN`,
  `CLIENT_ID`, `CLIENT_SECRET`, `TENANT_ID`, `JWT_KEY`,
  `FRPS_BIND_PORT`, `FRPS_AUTH_TOKEN`, `FRPS_HTTP_PORT`,
  `FRPS_DASHBOARD_PORT`, `FRPS_TCPMUX_PORT`, and `NIXSTASIS_SSH_FRP_HOST`
- Canonical internal Phoenix port: `4000`
- Canonical TLS approval path: `GET /api/v1/check_domain`
- Reserved public hosts: `nixstasis.<base-domain>`, `auth.<base-domain>`,
  and `frp-admin.<base-domain>`
- Laptop diagnostics: `NIXSTASIS_TLS_OBSERVATIONS_ENABLED=true` and
  `NIXSTASIS_TLS_OBSERVATIONS_TOKEN` enable token-protected TLS ask observations
  for local validation only.
- Browser terminal SSH uses `NIXSTASIS_SSH_FRP_HOST` plus `FRPS_TCPMUX_PORT` for
  the server-side FRPS TCP mux target. Compose sets the host to `frps`.
- `NIXSTASIS_SESSION_COOKIE_SECURE=false` is only for local dev/test release
  image builds that expose the loopback HTTP diagnostic UI. Production builds
  keep the default secure session cookie setting.

## Rewrite Status

From the migrated feature docs, the core server rewrite (devices, monitoring,
dashboard, and UI polish) is complete. Device list filtering, sorting, search,
selection, and bulk approval flows are implemented in the current LiveView and
API surface.

## Report View Improvements

Current scope for custom reports includes:

- Sortable and filterable Custom Reports list columns.
- Explicit row actions for `View`, `Edit`, and `Delete`.
- Delete confirmation modal before irreversible removal.
- Sortable and filterable report-detail results with operators:
  - `>`
  - `>=`
  - `==`
  - `<=`
  - `<`
- Session-backed preference restore for report list/detail view state.

Release-note summary:

- Added shared report table filtering/sorting utilities.
- Added report-list and report-detail interaction tests for sorting/filtering/actions.
- Added permission-gated behavior for manage/view report interactions.
