# Gateway FRP

The FRPS server that carries device tunnels for remote access. Devices connect out to it with `frpc`, so no inbound
ports are opened on devices. The tunnel carries SSH to the device's own `sshd`, which the client packages require,
and `frpc`'s admin API listens only on loopback.

## Owns

- The FRPS image built from `packages/frp/`: `download_frp.sh` fetches the release, and `frps-entrypoint.sh` runs
  `frps-render-config.sh` to fill `deploy/compose/frps/frps.toml` from the service environment, rejecting unknown
  template variables.
- The FRPS ports and the device-authorization plugin registration in `frps.toml`.

## Entry points

| Port                  | Exposure                                            | Used by                                                                           |
|-----------------------|-----------------------------------------------------|-----------------------------------------------------------------------------------|
| `FRPS_BIND_PORT`      | Published                                           | Device `frpc` connections.                                                        |
| `FRPS_HTTP_PORT`      | Internal to Compose                                 | Caddy's wildcard device hosts (`vhostHTTPPort`).                                  |
| `FRPS_TCPMUX_PORT`    | Internal to Compose                                 | Phoenix SSH terminals and PCP diagnostics over TCP mux (`tcpmuxHTTPConnectPort`). |
| `FRPS_DASHBOARD_PORT` | Internal; reached through `frp-admin.<base-domain>` | The admin dashboard, behind Caddy's admin-only policy and FRPS's own login.       |

## Boundaries

- **Device authorization:** the `nixstasis-device-authorization` HTTP plugin sends every Login and NewProxy to Phoenix
  at `/internal/frp/authorize`. Phoenix removes the user prefix from the proxy name, checks the route belongs to the
  device, and accepts only the credential for the device's current lease, so a revoked credential cannot ride on
  another lease. The lease rules are in [Server Devices](server-devices.md).
- **Teardown:** the plugin is only asked at login and when a proxy is created. A tunnel that is already up keeps
  running until the device's next heartbeat withdraws access and the client stops `frpc`.
- **Device hosts:** only Caddy publishes device HTTP access; the vhost port stays internal.
- **Terminals:** Phoenix opens SSH through the TCP mux with `ncat --proxy-type http`, finding the mux host through
  `NIXSTASIS_SSH_FRP_HOST`. SSH and PCP routes exist only while remote access is active; the Device page's PCP chart
  uses heartbeat telemetry instead of a live socket.
- **Provisioning:** an AtomixOS bootstrap first sends a read-only `HEAD /api/config` through the device host, which
  gives the device time to receive its lease on the next heartbeat (every 30 seconds with the packaged config, or 10 seconds when `poll.interval` is unset) and start `frpc` before any
  change. See [Server Provisioning](server-provisioning.md).
- The client side, including route profiles and how `frpc` is started, is described in
  [Client FRP Manager](client-frp-manager.md).
