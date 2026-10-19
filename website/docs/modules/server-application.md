# Server Application

The Elixir OTP application that starts the server and keeps its processes running.

## Owns

- The supervision tree, started by `Nixstasis.Application.start/2` in
  `packages/server/lib/nixstasis/application.ex` with a `:one_for_one` strategy under `Nixstasis.Supervisor`.
- Application and runtime configuration in `packages/server/config/config.exs` and `packages/server/config/runtime.exs`.
- The Mix project, dependencies, and aliases in `packages/server/mix.exs`.

## Entry points

The supervisor starts these children in order:

| Child                                                    | Responsibility                                                                          |
|----------------------------------------------------------|-----------------------------------------------------------------------------------------|
| `NixstasisWeb.Telemetry`                                 | Phoenix and VM telemetry metrics.                                                       |
| `Nixstasis.Repo`                                         | Ecto repository for PostgreSQL.                                                         |
| `Nixstasis.E2E.RetentionWorker`                          | Prunes old E2E runs; started unless E2E retention is disabled in config.                |
| `Nixstasis.Monitoring.TelemetryRetentionWorker`          | Prunes telemetry older than the retention window; started unless disabled.              |
| `DNSCluster`                                             | Node discovery when a DNS cluster query is configured.                                  |
| `Phoenix.PubSub` (`Nixstasis.PubSub`)                    | Broadcasts for LiveViews and channels.                                                  |
| `Nixstasis.Devices` (`:remote_access_leases`)            | Holds and restores remote-access leases and expires them.                               |
| `Nixstasis.Provisioning`                                 | Tracks AtomixOS bootstrap route leases and expires them.                                |
| `Nixstasis.Devices.SshKeyManager` (`:terminal_sessions`) | Issues ephemeral SSH keys for browser terminal sessions and expires them.               |
| `NixstasisWeb.RateLimiterStore`                          | ETS-backed rate-limit buckets, pruned every minute.                                     |
| `Nixstasis.Monitoring.OfflineChecker`                    | Marks devices offline when heartbeats stop.                                             |
| `Nixstasis.TLSObservations`                              | Keeps the most recent on-demand TLS approval decisions for the laptop diagnostics view. |
| `NixstasisWeb.Endpoint`                                  | The HTTP endpoint; started last so dependencies are ready before requests arrive.       |

Telemetry retention reads `NIXSTASIS_TELEMETRY_RETENTION_ENABLED`, `NIXSTASIS_TELEMETRY_RETENTION_DAYS`, and
`NIXSTASIS_TELEMETRY_RETENTION_INTERVAL_MS`; see
[Deployment Configuration](../reference/deployment-configuration.md#settings-compose-does-not-pass).

## Boundaries

- Each child that holds state keeps it in memory and reloads what it needs when it starts. If one crashes, only that
  one restarts.
- Domain behavior lives in [Server Domain](server-domain.md) and the context modules; HTTP and LiveView behavior lives
  in [Server Web](server-web.md).
- Development commands such as `mix setup` and `mix precommit` are covered in the
  [Development](../development.md) guide.
