# Gateway Caddy

The public front door. Caddy handles HTTPS, issues certificates on demand, signs operators in with AuthCrunch, and
routes traffic to Phoenix and FRPS. This page also sets out which routes skip operator sign-in, and how Caddy stops
anyone forging identity headers.

## Owns

- The production `deploy/compose/caddy/Caddyfile`, plus `Caddyfile.laptop` for laptop mode and `Caddyfile.dev` for local
  development.
- The Caddy image with the AuthCrunch plugin, built from `packages/caddy`.
- Mapping identity-provider groups to Nixstasis roles.

## Entry points

| Host                      | Purpose                                                                                           |
|---------------------------|---------------------------------------------------------------------------------------------------|
| `nixstasis.<base-domain>` | Operator UI and APIs, authenticated by AuthCrunch, plus the device and E2E routes that skip it.   |
| `*.<base-domain>`         | Device remote-access hosts, forwarded to the FRPS HTTP vhost after Phoenix authorizes the device. |
| `frp-admin.<base-domain>` | The FRPS dashboard, limited to the `nixstasis/admin` role.                                        |

On-demand TLS asks Phoenix `GET /api/v1/check_domain` before issuing a certificate. Device hosts are named
`atom-<normalized-device-id>`, optionally with a route suffix such as `-provisioning`, and are approved only while the
device has an unexpired remote-access lease.

## Boundaries

- **Routes that skip AuthCrunch:** device registration, heartbeat, command results, and command payloads, under both
  `/api/v1/devices` and `/api/json/device_runtime/devices`, and the E2E API under `/e2e/*`. Phoenix authenticates
  those with the device token or the E2E runner credential. The generated device list still requires an operator.
- **`/internal/frp/*`** returns `404` from the public gateway; only FRPS calls it, inside the Compose network.
- **Claim headers:** Caddy deletes any `X-Token-*` headers a client sends as soon as the request arrives, before
  AuthCrunch adds the verified ones. Don't move that deletion into the operator `reverse_proxy`: there it would remove
  the verified claims too. Phoenix trusts claims only alongside the `X-Nixstasis-Proxy-Token` proxy credential.
- **Connection-header trick:** a request whose `Connection` header lists an `X-Token-*` header or
  `X-Nixstasis-Proxy-Token` is rejected with `400` before sign-in. Otherwise a proxy could be tricked into stripping
  the verified headers as hop-by-hop headers. Ordinary `Connection: Upgrade` still works.
- **Client IP:** every proxy to Phoenix overwrites `X-Nixstasis-Client-IP` with the socket peer, and Phoenix uses it for
  rate limiting only when the proxy credential is present.
- **No device scope:** Caddy never forwards device scope. Phoenix ignores `X-Token-Device-Ids` and decides device
  access itself.
- **Roles:** AuthCrunch `transform user` blocks map the groups listed in `NIXSTASIS_VIEWER_GROUPS`,
  `NIXSTASIS_OPERATOR_GROUPS`, and `NIXSTASIS_ADMIN_GROUPS` to `nixstasis/viewer`, `nixstasis/operator`, and
  `nixstasis/admin`, so Phoenix stays independent of the identity provider.
- **Device hosts:** wildcard traffic deletes client claims, authenticates the operator, then asks Phoenix's internal FRP
  access endpoint whether that operator may reach the device named in the hostname.
- `deploy/compose/scripts/check_proxy_claims.py` checks these rules against both the production and laptop
  configurations; see [Local Stack](../development/local-stack.md#contract-validation).
