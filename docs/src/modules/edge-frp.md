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
  - `${FRPS_TCPMUX_PORT}`
- FRPS internal HTTP vhost port used only by Caddy wildcard proxying:
  - `${FRPS_HTTP_PORT}`
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

- The server stores remote-access intent and a named route-profile reference on
  devices. Operators or authorized API clients select the profile through the
  device update contract; the server stores only its bounded name.
- It exposes the active FRPS token and versioned `remote_access_profile`
  reference only through heartbeat responses.
- Client polling validates the profile reference against client-owned route
  definitions, then starts/stops FRPC through a transient systemd unit. A
  missing or empty token means FRPC should stop or remain stopped.
- The client renders a bounded `frpc.toml` from typed local routes. Supported
  routes include HTTPS `http2https`, plain HTTP loopback targets, and the
  existing SSH/PCP TCP mux routes; the built-in `atomixos-bootstrap` profile
  exposes `127.0.0.1:8080` as plain HTTP and rewrites the upstream `Host` header
  to the fixed local value `localhost`. Host rewrites are optional, restricted
  to plain HTTP routes, and validated as localhost or a loopback IP. The server
  never sends FRPC TOML, local targets, or header values.
- The FRPS auth token from the heartbeat response is passed from the launcher to
  `frp-session` through a root-only systemd `EnvironmentFile` rather than as a
  `systemd-run --setenv` value.
- Caddy proxies wildcard HTTP traffic to FRPS HTTP vhost port.
- The FRPS HTTP vhost port is internal to Compose; only Caddy publishes device
  HTTP access externally.
- Compose dev-lab clients can enable `nixstasis-simulator-http.service` to
  provide the local HTTPS target that FRPC proxies for HTTP-route smoke tests.
- The server provisioning action uses the same wildcard HTTP vhost for
  `POST /api/config` and `GET /api/jobs/<job_id>` through the authorized
  `atomixos-bootstrap` profile. It resolves only the documented relative job
  path and withdraws the lease after a terminal result.
- Server SSH terminal uses FRP TCP mux through `ncat --proxy-type http` and
  resolves the TCP mux host from `NIXSTASIS_SSH_FRP_HOST` in Compose.
- PCP diagnostic TCP mux routes are registered by the same on-demand FRPC
  session as SSH. They are not always-on; they exist only while remote access is
  requested for the device. The Device page PCP chart itself uses heartbeat
  telemetry rather than keeping a live PCP socket open from Phoenix.

Traceable references:

- `deploy/compose/frps/frps.toml:1-15`
- `deploy/compose/docker-compose.yml:33-66`
- `packages/client/internal/frp/manager.go:47-137`
- `packages/client/internal/config/route_profile.go`
- `packages/client/internal/frp/render.go`
- `packages/server/lib/nixstasis/devices/ssh_client.ex:30-49`
