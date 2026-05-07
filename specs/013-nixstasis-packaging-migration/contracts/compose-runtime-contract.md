# Contract: Compose Runtime Deployment

## Purpose

Define the operator-facing deployment contract for the supported `deploy/compose` stack.

## Stack Services

| Service | Required | Visibility | Contract |
| --- | --- | --- | --- |
| `caddy` | Yes | Public | Terminates HTTP/HTTPS, handles AuthCrunch authentication, proxies to Phoenix and FRPS, and owns public ingress for supported deployments. |
| `nixstasis` | Yes | Internal | Runs the Phoenix release on the canonical internal port and exposes the TLS approval endpoint. |
| `frps` | Yes | Mixed | Exposes explicit tunnel-related ports and uses pinned image/config inputs. |
| `postgres` | Profiled | Internal | Bundled database service enabled with the `bundled-db` profile. May be replaced by an external PostgreSQL service without changing application behavior. |

## Image References

- Supported release image references are pinned in Compose configuration.
- Operator `.env` files supply runtime settings and secrets, not mutable release image tags.
- Development or local-build image substitutions use Compose file composition with an additional override file.

## Canonical Operator Inputs

| Variable | Required | Applies To | Meaning |
| --- | --- | --- | --- |
| `DATABASE_URL` | Yes | `nixstasis` | PostgreSQL connection string. Points to bundled or external database. |
| `SECRET_KEY_BASE` | Yes | `nixstasis` | Phoenix application secret. |
| `PHX_HOST` | Yes | `nixstasis`, `caddy` | Public host for the application. |
| `PORT` | Yes | `nixstasis` | Canonical internal Phoenix port. Must remain `4000` for this feature. |
| `BASE_DOMAIN` | Yes | `caddy`, `frps`, `nixstasis` | Base domain used for reserved hosts and device subdomains. |
| `CLIENT_ID` | Yes | `caddy` | AuthCrunch OIDC client identifier. |
| `CLIENT_SECRET` | Yes | `caddy` | AuthCrunch OIDC client secret. |
| `TENANT_ID` | Yes | `caddy` | AuthCrunch tenant identifier. |
| `JWT_KEY` | Yes | `caddy` | AuthCrunch signing key material. |
| `FRPS_BIND_PORT` | Yes | `frps` | Control/bind port for FRPS. |
| `FRPS_HTTP_PORT` | Yes | `frps` | HTTP tunnel port for FRPS. |
| `FRPS_DASHBOARD_PORT` | Yes | `frps` | Dashboard/admin port for FRPS. |
| `FRPS_TCPMUX_PORT` | Yes | `frps` | TCP multiplexed SSH/terminal access port. |

## Canonical Routing Rules

- Phoenix listens internally on port `4000`.
- Caddy is required for all supported deployments and is the only supported public entrypoint to Phoenix.
- The canonical TLS approval endpoint is `GET /api/v1/check_domain`.
- Reserved public hosts are:
  - `nixstasis.<base-domain>`
  - `auth.<base-domain>`
  - `frp-admin.<base-domain>`
- Device remote-access hosts use:
  - `atom-<normalized-device-id>.<base-domain>`

## Database Modes

| Mode | Supported | Default | Contract |
| --- | --- | --- | --- |
| Bundled PostgreSQL | Yes | Profiled | Compose starts `postgres` only when the `bundled-db` profile is enabled and `DATABASE_URL` targets the bundled service. |
| External PostgreSQL | Yes | No | Operator supplies an external `DATABASE_URL`; application behavior and release commands remain unchanged. |

## Operational Rules

- Database migrations must be run explicitly and separately from application startup.
- Missing required operator inputs must fail fast through deployment documentation, templates, or startup validation.
- All externally sourced runtime artifacts used by the stack must be pinned and reproducible.
- Release image pins belong to Compose configuration; development overrides must use Compose file composition.
- No supported deployment path may bypass Caddy as the public ingress/authentication layer.
- Client-facing examples should target the public `nixstasis.<base-domain>` host
  while FRP device hosts use `atom-<normalized-device-id>.<base-domain>`.
