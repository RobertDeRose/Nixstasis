# Deployment Compose

## Language

- Docker Compose YAML and shell scripts.

## Runtime Context

- Supported production server deployment path.

## Purpose

- Defines and validates the deployable server stack composed of Phoenix, Caddy, FRPS, and optional PostgreSQL.

## Key Files

- `deploy/compose/docker-compose.yml`
- `deploy/compose/.env.example`
- `deploy/compose/dev.env`
- `deploy/compose/README.md`
- `deploy/compose/caddy/Caddyfile.laptop`
- `deploy/compose/scripts/dev-lab.sh`
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
  - FRPS bind, HTTP vhost, and TCP mux ports.
- Required operator inputs documented in `deploy/compose/README.md`:
  - `DATABASE_URL`
  - `SECRET_KEY_BASE`
  - `PHX_HOST`
  - `PORT`
  - `BASE_DOMAIN`
  - `CLIENT_ID`
  - `CLIENT_SECRET`
  - `TENANT_ID`
  - `JWT_KEY`
  - `FRPS_BIND_PORT`
  - `FRPS_AUTH_TOKEN`
  - `FRPS_HTTP_PORT`
  - `FRPS_DASHBOARD_PORT`
  - `FRPS_DASHBOARD_USER`
  - `FRPS_DASHBOARD_PASSWORD`
  - `FRPS_TCPMUX_PORT`

## Runtime Contract

- `DATABASE_URL`: PostgreSQL connection URL consumed by the Phoenix `nixstasis`
  service. It may point at bundled PostgreSQL or an external PostgreSQL host.
- `SECRET_KEY_BASE`: Phoenix release secret consumed by `nixstasis`.
- `PHX_HOST`: Public Phoenix host behind Caddy.
- `PORT`: Phoenix container port. The supported Compose deployment uses `4000`.
- `BASE_DOMAIN`: Root domain used for `nixstasis`, `auth`, `frp-admin`, and
  wildcard device hostnames.
- `CLIENT_ID`: Entra application client identifier consumed by Caddy auth.
- `CLIENT_SECRET`: Entra application secret consumed by Caddy auth.
- `TENANT_ID`: Entra tenant identifier consumed by Caddy auth.
- `JWT_KEY`: Caddy auth JWT signing key.
- `FRPS_BIND_PORT`: FRPS bind port for client tunnel connections.
- `FRPS_AUTH_TOKEN`: Shared FRPS auth token consumed by `frps`, `nixstasis`,
  and managed clients when remote access is requested.
- `FRPS_HTTP_PORT`: FRPS HTTP virtual host port used by Caddy wildcard proxying.
- `FRPS_DASHBOARD_PORT`: FRPS dashboard port used behind authenticated Caddy
  ingress.
- `FRPS_DASHBOARD_USER`: FRPS dashboard username.
- `FRPS_DASHBOARD_PASSWORD`: FRPS dashboard password.
- `FRPS_TCPMUX_PORT`: FRPS TCP mux port for TCP remote access.

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

- Docker Compose or rendered config for Apple Container `container-compose`.
- PostgreSQL image (always included; production can override `DATABASE_URL`).
- Pinned release image references from Compose configuration.

## Client-Server Interaction Details

- Compose deployment exposes the Phoenix app only through Caddy for HTTP ingress.
- Client configuration points at the public Caddy host.
- Bundled PostgreSQL starts automatically; production can override `DATABASE_URL`
  to point at an external managed database.
- Release image references are pinned in Compose configuration; local development
  builds images locally with `dev` tags.
- `packages/frp` currently provides FRPS image build assets and the shared FRP
  binary acquisition script used by server/client packaging flows.
- E2E endpoints are disabled by default in production and can be enabled for staging validation with `NIXSTASIS_E2E_ENABLED=true`.
- Development laptop mode uses the same single `docker-compose.yml` with a
  tracked `dev.env` file passed via `docker compose --env-file dev.env`.
- `deploy/compose/scripts/dev-lab.sh` starts the full stack, runs migrations,
  and seeds virtual devices for UI testing.
- `deploy/compose/caddy/Caddyfile.laptop` provides Caddy internal/local
  certificates for local HTTPS without public DNS.
- The `client` service is a device simulator running Ubuntu with systemd as PID 1,
  sshd, frpc, and the Go client binary — matching real device lifecycle.
- Default laptop mode uses `BASE_DOMAIN=localhost` with `nixstasis.localhost`,
  `auth.localhost`, `frp-admin.localhost`, and
  `atom-<normalized-device-id>.localhost`.
- Laptop-mode TLS uses Caddy internal/local certificates while preserving the same
  Phoenix ask endpoint at `GET /api/v1/check_domain`.
- Environment variables are passed to containers via explicit `environment:`
  blocks in the compose file; `--env-file` handles compose-time interpolation.

Traceable references:

- `deploy/compose/docker-compose.yml:1-129`
- `deploy/compose/README.md:1-117`
- `deploy/compose/scripts/check_runtime_contract.sh`
