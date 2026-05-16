# Edge FRP

## Language

- TOML configuration, Docker build assets, and Go client process integration.

## Runtime Context

- FRPS server in Compose deployment.
- FRPC process managed by the Go client on devices.

## Purpose

- Provides reverse proxy tunneling for managed devices so remote access can be exposed through server-side infrastructure.

## Key Files

- `deploy/compose/frps/frps.toml`
- `deploy/compose/docker-compose.yml`
- `packages/frp/Dockerfile`
- `packages/client/internal/frp/manager.go`
- `packages/client/build/root-dir/usr/share/nixstasis/frpc.toml`
- `packages/server/lib/nixstasis/devices/ssh_client.ex`

## Public Interfaces

- FRPS published ports from Compose:
  - `${FRPS_BIND_PORT}`
  - `${FRPS_HTTP_PORT}`
  - `${FRPS_TCPMUX_PORT}`
- FRPS internal dashboard port:
  - `${FRPS_DASHBOARD_PORT}`
- FRPS config fields:
  - `bindPort`
  - `auth.method = "token"`
  - `auth.token`
  - `webServer.port`
  - `webServer.user`
  - `webServer.password`
  - `tcpmuxHTTPConnectPort`
  - `vhostHTTPPort`
  - `subDomainHost`

## Dependencies

### Internal

- Caddy wildcard and dashboard reverse proxying.
- Go client FRPC manager.
- Server SSH terminal client.

### External

- FRP `frps` and `frpc` binaries.
- `ssh` and `ncat` for terminal sessions.

## Client-Server Interaction Details

- The server sets `remote_access_requested` on devices.
- Client polling reads heartbeat `remote_access_token` values and starts/stops
  FRPC through a transient systemd unit. A missing or empty token means FRPC
  should stop or remain stopped.
- FRPC reads `/usr/share/nixstasis/frpc.toml` directly; frpc expands runtime
  `{{ .Envs.* }}` placeholders from the session environment.
- The FRPS auth token from the heartbeat response is passed from the launcher to
  `frp-session` as a systemd credential rather than as a `systemd-run --setenv`
  value.
- Caddy proxies wildcard HTTP traffic to FRPS HTTP vhost port.
- Server SSH terminal uses FRP TCP mux through `ncat --proxy-type http`.

Traceable references:

- `deploy/compose/frps/frps.toml:1-15`
- `deploy/compose/docker-compose.yml:33-66`
- `packages/client/internal/frp/manager.go:47-137`
- `packages/server/lib/nixstasis/devices/ssh_client.ex:30-49`
