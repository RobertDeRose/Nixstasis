# Server Application

## Language

- Elixir.

## Runtime Context

- Server.
- OTP application and supervision tree.

## Purpose

- Starts and supervises the Phoenix server runtime, database repository, telemetry, PubSub, periodic workers, and endpoint.

## Key Files

- `packages/server/mix.exs`
- `packages/server/lib/nixstasis/application.ex`
- `packages/server/lib/nixstasis/repo.ex`
- `packages/server/lib/nixstasis_web/endpoint.ex`
- `packages/server/lib/nixstasis_web/telemetry.ex`
- `packages/server/config/config.exs`
- `packages/server/config/runtime.exs`

## Public Interfaces

- `Nixstasis.Application.start/2`
- `Nixstasis.Application.config_change/3`
- Mix aliases:
  - `mix setup`
  - `mix ecto.setup`
  - `mix phx.server`
  - `mix test`
  - `mix openapi.generate`
  - `mix precommit`

## Dependencies

### Internal

- `NixstasisWeb.Telemetry`
- `Nixstasis.Repo`
- `Nixstasis.E2E.RetentionWorker`
- `Nixstasis.Monitoring.TelemetryRetentionWorker`
- `Nixstasis.Monitoring.OfflineChecker`
- `NixstasisWeb.Endpoint`

### External

- Phoenix
- Phoenix LiveView
- Ecto/PostgreSQL
- Ash/AshPostgres/AshJsonApi/AshPhoenix
- Bandit
- DNSCluster
- Telemetry

## Runtime Notes

- `Nixstasis.E2E.RetentionWorker` is included only when E2E retention is enabled in app config.
- `Nixstasis.Monitoring.TelemetryRetentionWorker` prunes telemetry older than the configured window. Production enables it by default; `NIXSTASIS_TELEMETRY_RETENTION_ENABLED`, `NIXSTASIS_TELEMETRY_RETENTION_DAYS`, and `NIXSTASIS_TELEMETRY_RETENTION_INTERVAL_MS` configure it.
- The supervision strategy is `:one_for_one` with supervisor name `Nixstasis.Supervisor`.

Traceable references:

- `packages/server/mix.exs:1-113`
- `packages/server/lib/nixstasis/application.ex:9-51`
