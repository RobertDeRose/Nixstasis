# Nixstasis Server (Elixir/Phoenix)

The Nixstasis server is a Phoenix + LiveView application that provides the web UI and API for device monitoring,
approvals, alerts, and reporting.

## Features

- LiveView UI for fleet health, approvals, alerts, and reports.
- JSONB-backed device and telemetry storage (Postgres).
- API endpoints for device registration and heartbeat polling.
- Schema-driven dropdown APIs for alert/report builders:
  - `GET /api/v1/builder-schemas`
  - `GET /api/v1/builder-schemas/:schema_id/versions/:schema_version/options`
  - `POST /api/v1/builder-configurations/validate`
- Integrates with Caddy/AuthCrunch and FRP for secure remote access.

## Prerequisites

- Elixir `~> 1.19`
- Erlang/OTP (compatible with Elixir 1.19)
- Postgres

## Setup

```bash
mix setup
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

## Tests

```bash
mix test
```

## Configuration

- Runtime config: `config/runtime.exs`
- App config: `config/config.exs`
- Database config: `config/dev.exs`, `config/test.exs`

## Rewrite Status

From specs `001`, `002`, and `003`, the core server rewrite (devices, monitoring, dashboard, and UI polish) is
complete. The device list enhancement work in `specs/005-enhance-device-list` is still pending.

## Report View Improvements (Spec 010)

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
