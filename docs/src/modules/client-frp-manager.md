# Client FRP Manager

## Language

- Go.

## Runtime Context

- Client launcher for the bundled `frpc` transient systemd unit.

## Purpose

- Starts/stops the FRPC transient systemd unit, renders only client-owned typed
  routes, checks connection state through systemd, and reports state to heartbeat
  payloads.

## Key Files

- `packages/client/internal/frp/manager.go`
- `packages/client/internal/frp/types.go`
- `packages/client/internal/frp/manager_test.go`
- `packages/client/cmd/nixstasis/frp_session.go`
- `packages/client/cmd/nixstasis/frp_session_test.go`
- `packages/client/build/root-dir/usr/share/nixstasis/frpc.toml`
- `packages/client/build/root-dir/usr/share/nixstasis/config.example.yaml`
- `packages/client/internal/config/config.go`
- `packages/client/internal/config/route_profile.go`
- `packages/client/internal/frp/render.go`
- `packages/client/cmd/nixstasis/poll.go`

## Public Interfaces

- Types:
  - `Manager`
  - `ConnectionStatus`
- Functions and methods:
  - `NewManager`
  - `(*Manager).Start`
  - `(*Manager).Stop`
  - `(*Manager).IsActive`
  - `(*Manager).GetStatus`
  - `config.FRPCBinaryPath`
  - `config.FRPCConfigPath`

## Dependencies

### Internal

- `internal/config`

### External

- OS process execution via `os/exec`.
- systemd transient units via `systemd-run` and `systemctl`.

## Client-Server Interaction Details

- Heartbeat responses include `remote_access_token` and the optional
  versioned `remote_access_profile` reference only while remote access is
  requested for the device.
- If `remote_access_token` is non-empty and FRP is inactive, `pollOnce` resolves
  the named profile against client configuration, then starts the `nixstasis-frpc`
  transient unit using typed local routes and the heartbeat token. A token-only
  legacy response selects the local `default` profile.
- If `remote_access_token` is absent or empty and FRP is active, `pollOnce` stops
  FRPC.
- If the heartbeat token or selected profile changes while FRP is active,
  `pollOnce` performs one bounded stop/start restart with the current token.
- Unknown profile names, unsupported versions, non-loopback targets, and
  unsupported route/plugin kinds fail closed; the error is included in the next
  `connection_status.error` report and is cleared when remote access is withdrawn.
- Version 1 is the compatibility boundary for typed route kinds and controlled
  loopback targets. Future capabilities require client-declared typed support,
  security review, and a new profile version when route semantics change; the
  server never supplies route definitions, headers, or plugin options.
- FRP status is included in subsequent heartbeat requests as `connection_status`.
- Route profiles remain client-owned in `/etc/nixstasis/config.yaml`; the
  client renders a temporary typed `frpc.toml` and frpc expands its server/auth
  placeholders from the session environment. Route identifiers and the derived
  proxy names must be DNS-safe because HTTP subdomains and TCP mux custom domains
  are rendered from them.
- FRPS auth is passed to the transient unit through a root-only environment file
  and converted to `FRPS_AUTH_TOKEN` inside `frp-session`, avoiding token exposure
  in `systemd-run --setenv` metadata.
- If an unprivileged poll service is denied access to the system manager (as in
  the nested systemd Compose client), the manager starts a poll-owned
  `frp-session` child with the same bounded timeout and stops it when remote
  access is withdrawn. Native root-managed systemd installations retain the
  transient-unit path.

Traceable references:

- `packages/client/internal/frp/manager.go`
- `packages/client/cmd/nixstasis/frp_session.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/internal/config/config.go`
- `packages/client/internal/config/route_profile.go`
