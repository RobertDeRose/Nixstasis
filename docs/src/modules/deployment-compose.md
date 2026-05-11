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
- `deploy/compose/README.md`
- `deploy/compose/docker-compose.laptop.yml`
- `deploy/compose/laptop.env.example`
- `deploy/compose/caddy/Caddyfile.laptop`
- `deploy/compose/scripts/laptop.sh`
- `deploy/compose/scripts/laptop-client.sh`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `deploy/compose/scripts/render_compose.sh`
- `deploy/compose/scripts/validate_stack.sh`
- `prod.env`

## Public Interfaces

- Services:
  - `nixstasis`
  - `caddy`
  - `frps`
  - `postgres` under profile `bundled-db`
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

## Dependencies

### Internal

- `packages/server/Dockerfile`
- `packages/caddy/Dockerfile`
- `packages/frp/Dockerfile`
- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/frps/frps.toml`

### External

- Docker Compose or rendered config for Apple Container `container-compose`.
- PostgreSQL image when `bundled-db` profile is used.
- Pinned release image references from Compose configuration.

## Client-Server Interaction Details

- Compose deployment exposes the Phoenix app only through Caddy for HTTP ingress.
- Client configuration points at the public Caddy host.
- Bundled PostgreSQL startup requires the Compose `bundled-db` profile.
- Release image references are pinned in Compose configuration; local development image changes use an additional Compose override file instead of `.env` image-reference inputs.
- E2E endpoints are disabled by default in production and can be enabled for staging validation with `NIXSTASIS_E2E_ENABLED=true`.
- Development laptop mode keeps the base Compose file production-shaped and layers
  local-only behavior through separate override files.
- `deploy/compose/docker-compose.laptop.yml`, `deploy/compose/laptop.env.example`,
  and `deploy/compose/caddy/Caddyfile.laptop` are the default laptop-mode
  templates.
- `deploy/compose/scripts/laptop.sh` validates, starts, and stops default
  laptop mode with the laptop Compose override and ignored `laptop.env` file.
- `deploy/compose/scripts/laptop-client.sh` prepares ignored local Go-client state
  and runs `register` or `poll` against laptop mode without writing to `/etc`.
- The laptop Compose override includes a development-only `laptop-ssh` service on
  loopback so browser terminal validation can reach SSH through FRP.
- Default laptop mode uses `BASE_DOMAIN=localhost` with `nixstasis.localhost`,
  `auth.localhost`, `frp-admin.localhost`, and
  `atom-<normalized-device-id>.localhost`.
- Laptop-mode TLS uses Caddy internal/local certificates while preserving the same
  Phoenix ask endpoint at `GET /api/v1/check_domain`.

Traceable references:

- `deploy/compose/docker-compose.yml:1-90`
- `deploy/compose/README.md:5-90`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `deploy/compose/scripts/render_compose.sh`
