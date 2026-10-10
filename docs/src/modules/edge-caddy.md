# Edge Caddy

## Language

- Caddyfile configuration and Docker build assets.

## Runtime Context

- Edge reverse proxy, TLS termination, AuthCrunch authentication/authorization, and routing.

## Purpose

- Terminates public HTTPS traffic, performs on-demand TLS approval, hosts AuthCrunch portal, authorizes protected hosts, and reverse proxies to Phoenix and FRPS.

## Key Files

- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/caddy/Caddyfile.dev`
- `deploy/compose/caddy/Caddyfile.laptop`
- `packages/caddy/Dockerfile`
- `packages/caddy/bin/build_caddy.sh`

## Public Interfaces

- Public hosts:
  - `auth.{$BASE_DOMAIN}`
  - `nixstasis.{$BASE_DOMAIN}`
  - `frp-admin.{$BASE_DOMAIN}`
  - `*.{$BASE_DOMAIN}`
- Caddy on-demand TLS ask endpoint:
  - `http://nixstasis:${PORT}/api/v1/check_domain`
- AuthCrunch forwarded claim headers for Phoenix UI capability mapping:
  - `X-Token-Subject`
  - `X-Token-User-Email`
  - `X-Token-User-Name`
  - `X-Token-User-Roles`

`inject headers with claims` is the source for the default `X-Token-*` claim
headers. Production and laptop Nixstasis hosts delete client-supplied
`X-Token-*` headers at request entry, before AuthCrunch authorization injects
verified claims. Do not delete these headers in the operator `reverse_proxy`:
that would also remove the legitimate injected claims. Phoenix additionally
requires the matching Caddy-to-Phoenix proxy credential before trusting claims;
Caddy still enforces `authorize with entra_policy` on protected browser routes.

Before authorization or proxying, both configurations reject requests with `400`
when any `Connection` header names an `X-Token-*` header or
`X-Nixstasis-Proxy-Token`. Matching is case-insensitive and covers comma-separated
and repeated header fields. This prevents hop-by-hop cleanup from deleting a
verified device scope, which Phoenix would otherwise interpret as unscoped
access. Ordinary `Connection: Upgrade` requests remain supported.

Every Caddy-to-Phoenix proxy block also overwrites `X-Nixstasis-Client-IP` with
the socket peer address observed by Caddy. Phoenix consumes that value only when
`X-Nixstasis-Proxy-Token` authenticates the proxy; otherwise rate limiting uses
the direct Phoenix peer address. This keeps pre-authentication rate-limit keys
independent of attacker-controlled device IDs and forwarded-IP headers.

Group-to-role mapping happens in Caddy/AuthCrunch, not Phoenix. The production
environment provides provider-specific OIDC group values in
`NIXSTASIS_VIEWER_GROUPS`, `NIXSTASIS_OPERATOR_GROUPS`, and
`NIXSTASIS_ADMIN_GROUPS`; AuthCrunch `transform user` blocks add normalized
`nixstasis/viewer`, `nixstasis/operator`, and `nixstasis/admin` roles. This keeps
Phoenix provider-agnostic and lets any AuthCrunch-supported OIDC provider use the
same Nixstasis role contract.

## Dependencies

### Internal

- Phoenix service `nixstasis:${PORT}`.
- FRPS service ports.
- Compose environment variables.

### External

- Caddy.
- AuthCrunch/Caddy security plugin.
- Azure OAuth identity provider configuration.
- ACME/on-demand TLS.

## Client-Server Interaction Details

- Browser/operator HTTPS traffic to `nixstasis.<base-domain>` is authorized by
  AuthCrunch before proxying to Phoenix.
- Default local dev/test HTTPS uses `Caddyfile.dev`, which is loopback-bound by
  `dev.env` and relies on Phoenix's explicit local auth fallback instead of a
  live OIDC provider.
- Device protocol HTTPS traffic on `nixstasis.<base-domain>` bypasses AuthCrunch
  only for registration, heartbeat, command result, and command payload routes
  under both `/api/v1/devices` and `/api/json/device_runtime/devices`;
  Phoenix enforces the device credential contract for those runtime calls.
  Generated device listing remains operator-authenticated.
- The Caddy image workflow runs real signed-JWT proxy checks for both production
  and laptop configurations through `check_runtime_contract.sh` with `CADDY_BIN`.
  These use loopback HTTP and an echo upstream, checking device claim removal,
  operator claim injection, optional scope injection, proxy-token overwrite,
  rejection of trusted-header `Connection` nominations before upstream access,
  and preservation of WebSocket upgrade headers; they do not exercise TLS,
  OIDC login, or a full WebSocket handshake. See the
  [Compose validation commands](deployment-compose.md#contract-validation).
- Wildcard device traffic is routed to FRPS HTTP vhost port.
- FRPS dashboard traffic is routed through `frp-admin.<base-domain>`.
- TLS certificate issuance calls Phoenix `GET /api/v1/check_domain` to approve domains.
  Device hosts use the normalized device UUID, with an optional route suffix such
  as `-provisioning`. Approval requires requested remote access with a persisted,
  unexpired lease; a missing or expired lease is denied.

Traceable references:

- `deploy/compose/caddy/Caddyfile:1-75`
- `README.md:319-350`
- `deploy/compose/README.md:7-20`
