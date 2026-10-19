# Deployment

Docker Compose under `deploy/compose` is the supported way to run the Nixstasis server. This page covers what the stack
contains and how to start it; every environment variable is listed in
[Deployment Configuration](../reference/deployment-configuration.md), and the local development stack is described in
[Local Stack](../development/local-stack.md).

## Services

| Service     | Role                                                                                                              | Exposure                                                                                     |
|-------------|-------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `nixstasis` | The Nixstasis server and web UI.                                                                                  | Loopback only, on `PHOENIX_BIND_HOST:PORT`, for diagnostics.                                 |
| `caddy`     | Public HTTPS, on-demand TLS, and AuthCrunch ([Gateway Caddy](../modules/gateway-caddy.md)).                       | Ports 80 and 443 on `BIND_HOST`.                                                             |
| `frps`      | Device tunnels ([Gateway FRP](../modules/gateway-frp.md)).                                                        | `FRPS_BIND_PORT` on `BIND_HOST`; its HTTP vhost, TCP mux, and dashboard ports stay internal. |
| `postgres`  | The bundled database, always defined; point `DATABASE_URL` elsewhere to use an external one.                      | Internal.                                                                                    |
| `client`    | A device simulator for development: Ubuntu with systemd, `sshd`, `frpc`, PCP, and the client. It runs privileged. | Internal.                                                                                    |

Browser traffic reaches the server only through Caddy. A direct caller cannot forge operator identity, because the server
trusts `X-Token-*` claims only together with the `NIXSTASIS_PROXY_AUTH_TOKEN` credential that Caddy adds.

## Start a production stack

1. Copy `deploy/compose/.env.example` to `.env` and fill every required value. Generate `NIXSTASIS_PROXY_AUTH_TOKEN`
   with `openssl rand -hex 32`; quotes around the value do not count toward its 32-character minimum.
2. Set `BIND_HOST=0.0.0.0`, keep `PHOENIX_BIND_HOST=127.0.0.1`, and set `CADDY_CONFIG=./caddy/Caddyfile`.
3. Set the `NIXSTASIS_*_IMAGE_REF` values to digest-pinned GHCR references.
4. Run migrations, which never run implicitly at startup:

   ```sh
   docker compose --env-file .env run --rm nixstasis /app/bin/migrate
   ```

5. Start the server services, leaving out the `client` simulator:

   ```sh
   docker compose --env-file .env up -d nixstasis caddy frps postgres
   ```

6. Confirm the stack with [Health Checks](health-checks.md).

## Hostnames

| Host                                        | Serves                                                                           |
|---------------------------------------------|----------------------------------------------------------------------------------|
| `nixstasis.<base-domain>`                   | The operator UI and the device and E2E APIs.                                     |
| `auth.<base-domain>`                        | AuthCrunch sign-in and OIDC callbacks.                                           |
| `frp-admin.<base-domain>`                   | The FRPS dashboard, for `nixstasis/admin` only, behind FRPS's own login as well. |
| `atom-<normalized-device-id>.<base-domain>` | Device remote access through FRPS, with certificates approved by `check_domain`. |

## Managed devices

Devices point their API URL at `https://nixstasis.<base-domain>`; see
[Client Installation](client-installation.md). They verify certificates, so a deployment that uses a private CA must
install its public certificate on each device.

## Artifact rules

- Images and other externally sourced artifacts are pinned by digest or checksum.
- Database migrations are a separate step from startup.
- Client packages bundle `frpc` at `/usr/libexec/nixstasis/frpc`, so devices need no separate FRP package.
