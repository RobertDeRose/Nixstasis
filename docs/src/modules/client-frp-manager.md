# Client FRP Manager

## Language

- Go.

## Runtime Context

- Client process manager for bundled `frpc`.

## Purpose

- Renders FRPC configuration, starts/stops the FRPC process, tracks FRP connection state, and reports state to heartbeat payloads.

## Key Files

- `packages/client/internal/frp/manager.go`
- `packages/client/internal/frp/types.go`
- `packages/client/internal/frp/manager_test.go`
- `packages/client/build/root-dir/etc/nixstasis/frpc.toml`
- `packages/client/internal/config/config.go`
- `packages/client/cmd/nixstasis/poll.go`

## Public Interfaces

- Types:
  - `Manager`
  - `ConnectionStatus`
- Functions and methods:
  - `NewManager`
  - `(*Manager).Start`
  - `(*Manager).StartWithConfig`
  - `(*Manager).Stop`
  - `(*Manager).GetStatus`
  - `config.FRPCBinaryPath`
  - `config.FRPCConfigPath`

## Dependencies

### Internal

- `internal/config`

### External

- OS process execution via `os/exec`.
- Temporary filesystem for rendered config files.

## Client-Server Interaction Details

- Heartbeat responses include `remote_access_requested`.
- If `remote_access_requested` is true and FRP is inactive, `pollOnce` starts FRPC using configured FRP values.
- If `remote_access_requested` is false and FRP is active, `pollOnce` stops FRPC.
- FRP status is included in subsequent heartbeat requests as `connection_status`.

Traceable references:

- `packages/client/internal/frp/manager.go:21-169`
- `packages/client/cmd/nixstasis/poll.go:111-154`
- `packages/client/internal/config/config.go:121-129`
