# Client FRP Manager

## Language

- Go.

## Runtime Context

- Client launcher for the bundled `frpc` transient systemd unit.

## Purpose

- Starts/stops the FRPC transient systemd unit, passes runtime template values to
  frpc, checks connection state through systemd, and reports state to heartbeat
  payloads.

## Key Files

- `packages/client/internal/frp/manager.go`
- `packages/client/internal/frp/types.go`
- `packages/client/internal/frp/manager_test.go`
- `packages/client/cmd/nixstasis/frp_session.go`
- `packages/client/cmd/nixstasis/frp_session_test.go`
- `packages/client/build/root-dir/usr/share/nixstasis/frpc.toml`
- `packages/client/internal/config/config.go`
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

- Heartbeat responses include `remote_access_token` only while remote access is
  requested for the device.
- If `remote_access_token` is non-empty and FRP is inactive, `pollOnce` starts
  the `nixstasis-frpc` transient unit using configured non-secret FRP values and
  the heartbeat token.
- If `remote_access_token` is absent or empty and FRP is active, `pollOnce` stops
  FRPC.
- If the heartbeat token changes while FRP is active, `pollOnce` restarts FRPC
  with the current token.
- FRP status is included in subsequent heartbeat requests as `connection_status`.
- `frpc.toml` remains client-owned in `/usr/share/nixstasis/frpc.toml` and frpc
  expands `{{ .Envs.* }}` placeholders from the session environment.
- FRPS auth is passed to the transient unit as a systemd credential and converted
  to `FRPS_AUTH_TOKEN` inside `frp-session`, avoiding token exposure in
  `systemd-run --setenv` metadata.

Traceable references:

- `packages/client/internal/frp/manager.go`
- `packages/client/cmd/nixstasis/frp_session.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/internal/config/config.go`
