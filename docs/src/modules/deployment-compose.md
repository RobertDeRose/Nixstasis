# Deployment Compose

## Language

- Docker Compose YAML and shell scripts.

## Runtime Context

- Supported production server deployment path.
- Production operations runbooks live in `docs/src/operations/` and document
  backup, restore, rotation, incident response, upgrade, and HA boundary
  procedures for this deployment path.

## Purpose

- Defines and validates the deployable server stack composed of Phoenix, Caddy, FRPS, and optional PostgreSQL.

## Key Files

- `deploy/compose/docker-compose.yml`
- `deploy/compose/.env.example`
- `deploy/compose/dev.env`
- `deploy/compose/README.md`
- `deploy/compose/caddy/Caddyfile.dev`
- `deploy/compose/caddy/Caddyfile.laptop`
- `.mise/tasks/deploy/dev.sh`
- `.mise/tasks/deploy/dev/seed.sh`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `deploy/compose/scripts/validate_stack.sh`
- `prod.env`

## Public Interfaces

- Services:
  - `nixstasis`
  - `caddy`
  - `frps`
  - `postgres`
  - `client`
- Public published ports:
  - Caddy `80:80`
  - Caddy `443:443`
  - FRPS bind and TCP mux ports.
- Required operator inputs documented in `deploy/compose/README.md`:
  - `DATABASE_URL`
  - `SECRET_KEY_BASE`
  - `PHX_HOST`
  - `PORT`
  - `PHOENIX_BIND_HOST`
  - `BASE_DOMAIN`
  - `CLIENT_ID`
  - `CLIENT_SECRET`
  - `TENANT_ID`
  - `JWT_KEY`
  - `AUTHORIZED_ROLES`
  - `AUTHORIZED_GROUPS`
  - `NIXSTASIS_VIEWER_GROUPS`
  - `NIXSTASIS_OPERATOR_GROUPS`
  - `NIXSTASIS_ADMIN_GROUPS`
  - `FRPS_BIND_PORT`
  - `FRPS_AUTH_TOKEN`
  - `FRPS_HTTP_PORT`
  - `FRPS_DASHBOARD_PORT`
  - `FRPS_DASHBOARD_USER`
  - `FRPS_DASHBOARD_PASSWORD`
  - `FRPS_TCPMUX_PORT`
  - `NIXSTASIS_SSH_FRP_HOST`

## Runtime Contract

- `DATABASE_URL`: PostgreSQL connection URL consumed by the Phoenix `nixstasis`
  service. It may point at bundled PostgreSQL or an external PostgreSQL host.
- `SECRET_KEY_BASE`: Phoenix release secret consumed by `nixstasis`.
- `PHX_HOST`: Public Phoenix host behind Caddy.
- `PORT`: Phoenix container port. The supported Compose deployment uses `4000`.
- `PHOENIX_BIND_HOST`: host bind address for Phoenix's optional direct diagnostic
  port. Production keeps this at `127.0.0.1`; public browser access is supported
  only through Caddy/AuthCrunch.
- `NIXSTASIS_SESSION_COOKIE_SECURE`: build-time Phoenix release setting for the
  browser session cookie. Production keeps this `true`; tracked local dev/test
  sets it to `false` so the loopback HTTP diagnostic UI can maintain LiveView
  sessions.
- `BASE_DOMAIN`: Root domain used for `nixstasis`, `auth`, `frp-admin`, and
  wildcard device hostnames.
- `CLIENT_ID`: Entra application client identifier consumed by Caddy auth.
- `CLIENT_SECRET`: Entra application secret consumed by Caddy auth.
- `TENANT_ID`: Entra tenant identifier consumed by Caddy auth.
- `JWT_KEY`: Caddy auth JWT signing key.
- `AUTHORIZED_ROLES`: normalized Caddy/AuthCrunch roles allowed at the edge.
  Production should include `nixstasis/viewer`, `nixstasis/operator`, and
  `nixstasis/admin` as needed.
- `AUTHORIZED_GROUPS`: provider-specific OIDC groups allowed at the edge. Keep
  this as the union of the `NIXSTASIS_*_GROUPS` values.
- `NIXSTASIS_VIEWER_GROUPS`, `NIXSTASIS_OPERATOR_GROUPS`, and
  `NIXSTASIS_ADMIN_GROUPS`: provider-specific OIDC group values that Caddy
  transforms into provider-generic `nixstasis/*` roles before proxying to
  Phoenix.
- `FRPS_BIND_PORT`: FRPS bind port for client tunnel connections.
- `FRPS_AUTH_TOKEN`: Shared FRPS auth token consumed by `frps`, `nixstasis`,
  and managed clients when remote access is requested.
- `FRPS_HTTP_PORT`: internal FRPS HTTP virtual host port used by Caddy wildcard
  proxying; it is not published directly on the host.
- `FRPS_DASHBOARD_PORT`: FRPS dashboard port used behind authenticated Caddy
  ingress.
- `FRPS_DASHBOARD_USER`: FRPS dashboard username.
- `FRPS_DASHBOARD_PASSWORD`: FRPS dashboard password.
- `FRPS_TCPMUX_PORT`: FRPS TCP mux port for TCP remote access.
- `NIXSTASIS_SSH_FRP_HOST`: hostname the Phoenix server uses for outbound SSH
  terminal connections to FRPS TCP mux. Compose sets this to the internal
  `frps` service name; external deployments should use the reachable FRPS host.
- `NIXSTASIS_API_URL`: optional client simulator API URL. Local development
  defaults it to the Compose-internal Phoenix service so systemd-managed client
  services can register before any public DNS is available.
- `NIXSTASIS_FRP_HTTP_LOCAL_ADDR`: optional client simulator FRPC local HTTPS
  target. Local development defaults it to `127.0.0.1:443`.
- `NIXSTASIS_SIMULATOR_HTTP_ENABLED`: enables the client simulator's local HTTPS
  endpoint for FRP HTTP-route smoke tests. Dev enables it; production examples
  keep it disabled.
- Browser terminal SSH uses the dedicated `nixstasis-support` account and the
  fixed client/helper IPC socket `/run/nixstasis/ssh-authority.sock`. The
  service identity is `nixstasis`; `nixstasis-ssh-authority` is the locked
  `AuthorizedKeysCommandUser`. New installs use `AuthorizedKeysFile none` and
  do not write browser-terminal keys to a persistent file.

### Hostnames

- `nixstasis.<base-domain>`: public Phoenix application host behind Caddy.
- `auth.<base-domain>`: AuthCrunch/OIDC callback and auth host.
- `frp-admin.<base-domain>`: authenticated FRPS dashboard host.
- `atom-<normalized-device-id>.<base-domain>`: device remote-access host pattern
  routed through Caddy wildcard TLS and FRPS HTTP vhost support.

### Endpoints

- `check_domain`: Phoenix ask endpoint used by Caddy on-demand TLS to authorize
  wildcard device hostnames before proxying to FRPS.

### Artifact Rules

- Server startup and database migrations are separate operations; application
  startup must not implicitly run migrations.
- Externally sourced runtime artifacts must be pinned by digest or checksum.
- Client release artifacts install bundled `frpc` at
  `/usr/libexec/nixstasis/frpc` so managed devices do not depend on a separate
  FRP package.

## Dependencies

### Internal

- `packages/server/Dockerfile`
- `packages/caddy/Dockerfile`
- `packages/frp/Dockerfile`
- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/frps/frps.toml`
- `packages/frp/bin/download_frp.sh`

### External

- Docker Compose.
- PostgreSQL image (always included; production can override `DATABASE_URL`).
- Pinned release image references from Compose configuration.

## Client-Server Interaction Details

- Compose deployment exposes the Phoenix app only through Caddy for public HTTP
  ingress; the direct Phoenix host port remains loopback-bound for diagnostics.
- External managed devices point at the public Caddy host. The local Compose
  client simulator writes `/etc/nixstasis/config.yaml` from Compose environment
  before systemd starts and uses the Compose-internal Phoenix and FRPS services.
- Bundled PostgreSQL starts automatically; production can override `DATABASE_URL`
  to point at an external managed database.
- The bundled PostgreSQL volume mounts at `/var/lib/postgresql` for compatibility
  with PostgreSQL 18+ image data directories.
- The Compose client provisions `/run/nixstasis` for the poll service and uses
  the same fixed SSH authority socket as the installed helper; custom socket
  paths are not part of the supported deployment contract.
- Release image references are pinned in Compose configuration; local development
  builds images locally with `dev` tags.
- `packages/frp` currently provides FRPS image build assets and the shared FRP
  binary acquisition script used by server/client packaging flows.
- E2E endpoints are disabled by default in production and can be enabled for staging validation with `NIXSTASIS_E2E_ENABLED=true`.
- Development laptop mode uses the same single `docker-compose.yml` with a
  tracked `dev.env` file passed via `docker compose --env-file dev.env`.
- The tracked local dev/test image build passes
  `NIXSTASIS_SESSION_COOKIE_SECURE=false`; production builds must keep the
  default secure cookie setting.
- `mise run deploy:dev -- up` wraps `.mise/tasks/deploy/dev.sh up` to
  start the full stack, run migrations, and pre-approve running client simulators.
- `mise run deploy:dev:seed` runs the tracked Compose RPC fixture task for
  schema-builder devices, versions, telemetry, an alert, and a report. The task
  is idempotent for its stable fixtures and is the supported place to extend
  local builder test data; it requires a running dev lab.
- `mise run deploy:dev -- down` removes dev-lab containers and named volumes,
  including local PostgreSQL data, so the next `up` starts from an empty database.
- `deploy/compose/caddy/Caddyfile.dev` provides default loopback-only local HTTPS
  without real OIDC credentials. `deploy/compose/caddy/Caddyfile.laptop` remains
  available for local AuthCrunch validation with real OIDC credentials.
- The `client` service is a device simulator running Ubuntu with systemd as PID 1,
  sshd, frpc, PCP services, and the Go client binary — matching real device
  lifecycle.
- If the client image is run outside systemd with an explicit command, its
  entrypoint starts PCP directly before executing that command for PCP tooling
  validation.
- The client image keeps `systemd-user-sessions.service` in `multi-user.target`
  so `/run/nologin` is removed during boot and remote SSH sessions can log in as
  the dedicated `nixstasis-support` account. The Go client continues to use the
  separate `nixstasis` service account.
- The tracked dev env also enables `nixstasis-simulator-http.service`, a local
  HTTPS endpoint on `127.0.0.1:443`, so wildcard device hosts can be tested
  through Caddy, FRPS, FRPC, and a real client-local listener.
- Dev-lab pre-approves running client container MAC addresses after startup so
  the retrying registration service can receive a runtime token.
- `--clients` starts real Go client containers for registration, polling, FRP,
  PCP telemetry, and SSH remote-access validation. The dev-lab does not seed
  database-only virtual devices.
- Client application logs live in journald inside the systemd container and are
  exposed through `mise run deploy:dev -- client-logs`.
- The Device page PCP tab uses PCP-derived heartbeat telemetry. Direct PCP access
  through FRP is scoped to an active remote-access lease because FRPC runs only
  while the server requests remote access.
- Default laptop mode uses `BASE_DOMAIN=localhost` with `nixstasis.localhost`,
  `auth.localhost`, `frp-admin.localhost`, and
  `atom-<normalized-device-id>.localhost`.
- Laptop-mode TLS uses Caddy internal/local certificates directly for
  deterministic local HTTPS. Production Caddy still uses the Phoenix ask endpoint
  at `GET /api/v1/check_domain` for on-demand TLS approval.
- Environment variables are passed to containers via explicit `environment:`
  blocks in the compose file; `--env-file` handles compose-time interpolation.

Traceable references:

- `deploy/compose/docker-compose.yml:1-129`
- `deploy/compose/README.md:1-117`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `docs/src/operations/index.md`
