# Deployment Configuration

Environment variables for the Docker Compose deployment. Production values go in `.env`, starting from
`deploy/compose/.env.example`; the tracked `deploy/compose/dev.env` holds local development values. Compose passes
values to containers through explicit `environment:` blocks, and `--env-file` handles interpolation. How to deploy is
described in [Deployment](../operations/deployment.md).

## Phoenix

| Variable                                                                 | Purpose                                                                                                                                                                               |
|--------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `DATABASE_URL`                                                           | PostgreSQL connection URL, for the bundled `postgres` service or an external database.                                                                                                |
| `SECRET_KEY_BASE`                                                        | Phoenix release secret.                                                                                                                                                               |
| `PHX_HOST`                                                               | The public Phoenix host behind Caddy.                                                                                                                                                 |
| `PORT`                                                                   | Phoenix container port; Compose uses `4000`.                                                                                                                                          |
| `PHOENIX_BIND_HOST`                                                      | Host address for Phoenix's direct diagnostic port. Keep `127.0.0.1` in production.                                                                                                    |
| `NIXSTASIS_SESSION_COOKIE_SECURE`                                        | Build-time secure-cookie setting. Production keeps `true`; local development builds use `false` for the loopback HTTP UI.                                                             |
| `NIXSTASIS_FORCE_SSL`                                                    | Enforces HTTPS with HSTS, honoring `X-Forwarded-Proto` from Caddy; defaults to `true`.                                                                                                |
| `CHECK_ORIGIN_EXTRA`                                                     | Extra allowed WebSocket origins; defaults to `localhost,127.0.0.1`.                                                                                                                   |
| `NIXSTASIS_PROXY_AUTH_TOKEN`                                             | Secret of at least 32 bytes shared only by Caddy and Phoenix. Caddy sets `X-Nixstasis-Proxy-Token` on every proxied request, and Phoenix trusts operator claims only when it matches. |
| `NIXSTASIS_SSH_FRP_HOST`                                                 | Host Phoenix uses for SSH terminal connections through the FRPS TCP mux; Compose uses the internal `frps` service.                                                                    |
| `NIXSTASIS_E2E_ENABLED`                                                  | Enables the `/e2e` API; disabled by default.                                                                                                                                          |
| `NIXSTASIS_E2E_RUNNER_ID`, `NIXSTASIS_E2E_RUNNER_TOKEN`                  | The E2E runner identity and its token of at least 32 bytes; required when E2E is enabled.                                                                                             |
| `NIXSTASIS_TLS_OBSERVATIONS_ENABLED`, `NIXSTASIS_TLS_OBSERVATIONS_TOKEN` | Development-only TLS decision diagnostics; disabled by default.                                                                                                                       |
| `NIXSTASIS_LOCAL_BROWSER_AUTH_FALLBACK`                                  | Development-only operator identity when no claim headers arrive.                                                                                                                      |

## Caddy and AuthCrunch

| Variable                                                                         | Purpose                                                                                                           |
|----------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| `BASE_DOMAIN`                                                                    | Root domain for the `nixstasis`, `auth`, `frp-admin`, and device hostnames.                                       |
| `BIND_HOST`                                                                      | Host address for the published Caddy and FRPS ports; `0.0.0.0` in production.                                     |
| `CADDY_CONFIG`                                                                   | Caddyfile to mount: `./caddy/Caddyfile` in production.                                                            |
| `ACME_EMAIL`                                                                     | Contact address for certificate issuance.                                                                         |
| `CLIENT_ID`, `CLIENT_SECRET`, `TENANT_ID`                                        | The Entra application used for operator sign-in.                                                                  |
| `JWT_KEY`                                                                        | AuthCrunch token signing key.                                                                                     |
| `AUTHORIZED_ROLES`                                                               | Normalized roles allowed at the gateway, such as `nixstasis/viewer`, `nixstasis/operator`, and `nixstasis/admin`. |
| `AUTHORIZED_GROUPS`                                                              | Identity-provider groups allowed at the gateway; keep it the union of the three group variables below.            |
| `NIXSTASIS_VIEWER_GROUPS`, `NIXSTASIS_OPERATOR_GROUPS`, `NIXSTASIS_ADMIN_GROUPS` | Provider groups that Caddy maps to each `nixstasis/*` role.                                                       |

## FRPS

| Variable                                                                | Purpose                                                             |
|-------------------------------------------------------------------------|---------------------------------------------------------------------|
| `FRP_VERSION`                                                           | Pinned FRP release used by the FRPS image and the client simulator. |
| `FRPS_BIND_PORT`                                                        | Published port that device `frpc` connects to.                      |
| `FRPS_HTTP_PORT`                                                        | Internal HTTP vhost port that Caddy forwards device hosts to.       |
| `FRPS_TCPMUX_PORT`                                                      | Internal TCP mux port that Phoenix uses for SSH and PCP.            |
| `FRPS_DASHBOARD_PORT`, `FRPS_DASHBOARD_USER`, `FRPS_DASHBOARD_PASSWORD` | The FRPS dashboard, reached through `frp-admin.<base-domain>`.      |

FRPS has no deployment-wide device secret: Phoenix authorizes each Login and NewProxy using short-lived, signed device
credentials.

## Settings Compose does not pass

Phoenix also reads `NIXSTASIS_TELEMETRY_RETENTION_ENABLED`, `NIXSTASIS_TELEMETRY_RETENTION_DAYS`, and
`NIXSTASIS_TELEMETRY_RETENTION_INTERVAL_MS`, but the Compose file does not pass them to the container, so setting them in
`.env` has no effect. Compose deployments use the defaults: retention enabled, 30 days, swept daily.

## PostgreSQL

| Variable                                            | Purpose                                |
|-----------------------------------------------------|----------------------------------------|
| `POSTGRES_VERSION`                                  | Bundled PostgreSQL image tag.          |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | Bundled database name and credentials. |

## Images

`NIXSTASIS_SERVER_IMAGE_REF`, `NIXSTASIS_CADDY_IMAGE_REF`, `NIXSTASIS_FRPS_IMAGE_REF`, and `NIXSTASIS_CLIENT_IMAGE_REF`
select the images; production uses digest-pinned GHCR references.

## Client simulator

| Variable                           | Purpose                                                                                |
|------------------------------------|----------------------------------------------------------------------------------------|
| `NIXSTASIS_API_URL`                | The simulator's API URL; defaults to `https://nixstasis.${BASE_DOMAIN}` through Caddy. |
| `NIXSTASIS_FRP_HTTP_LOCAL_ADDR`    | The simulator's local HTTPS target for FRP HTTP routes; defaults to `127.0.0.1:443`.   |
| `NIXSTASIS_SIMULATOR_HTTP_ENABLED` | Starts the simulator's local HTTPS endpoint for HTTP route tests; disabled by default. |
