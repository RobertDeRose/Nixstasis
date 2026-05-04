# Edge Caddy

## Language

- Caddyfile configuration and Docker build assets.

## Runtime Context

- Edge reverse proxy, TLS termination, AuthCrunch authentication/authorization, and routing.

## Purpose

- Terminates public HTTPS traffic, performs on-demand TLS approval, hosts AuthCrunch portal, authorizes protected hosts, and reverse proxies to Phoenix and FRPS.

## Key Files

- `deploy/compose/caddy/Caddyfile`
- `packages/caddy/Dockerfile`
- `packages/caddy/bin/build_caddy.sh`

## Public Interfaces

- Public hosts:
  - `auth.{$BASE_DOMAIN}`
  - `nixstasis.{$BASE_DOMAIN}`
  - `frp-admin.{$BASE_DOMAIN}`
  - `*.{$BASE_DOMAIN}`
- Caddy on-demand TLS ask endpoint:
  - `http://nixstasis:4000/api/v1/check_domain`

## Dependencies

### Internal

- Phoenix service `nixstasis:4000`.
- FRPS service ports.
- Compose environment variables.

### External

- Caddy.
- AuthCrunch/Caddy security plugin.
- Azure OAuth identity provider configuration.
- ACME/on-demand TLS.

## Client-Server Interaction Details

- Browser and client HTTPS traffic to `nixstasis.<base-domain>` is routed to Phoenix.
- Wildcard device traffic is routed to FRPS HTTP vhost port.
- FRPS dashboard traffic is routed through `frp-admin.<base-domain>`.
- TLS certificate issuance calls Phoenix `GET /api/v1/check_domain` to approve domains.

Traceable references:
- `deploy/compose/caddy/Caddyfile:1-75`
- `README.md:319-350`
- `deploy/compose/README.md:7-20`
