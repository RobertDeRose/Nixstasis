# Client CLI

## Language

- Go.

## Runtime Context

- Client compiled binary.
- Cobra-based CLI command tree.

## Purpose

- Provides the `nixstasis` executable for registration, polling, and script management.

## Key Files

- `packages/client/cmd/nixstasis/main.go`
- `packages/client/cmd/nixstasis/register.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/cmd/nixstasis/script.go`
- `packages/client/cmd/nixstasis/install_script.go`
- `packages/client/cmd/nixstasis/list_scripts.go`
- `packages/client/cmd/nixstasis/remove_script.go`
- `packages/client/cmd/nixstasis/test_script.go`
- `packages/client/cmd/nixstasis/repl.go`

## Public Interfaces

- CLI commands:
  - `nixstasis register`
  - `nixstasis poll`
  - `nixstasis script install <path>`
  - `nixstasis script list`
  - `nixstasis script remove`
  - `nixstasis script test`
  - `nixstasis script repl`
- Go functions:
  - `main`
  - `runMain`
  - `run`
  - `shouldSkipConfig`
  - `runRegister`
  - `runPoll`
  - `pollOnce`
  - `pollInterval`

## Dependencies

### Internal

- `internal/config`
- `internal/logging`
- `internal/identity`
- `internal/transport`
- `internal/script`
- `internal/frp`
- `internal/commands`
- `internal/telemetry`

### External

- `github.com/spf13/cobra`
- `github.com/spf13/viper`
- Go `runtime/trace` flight recorder.

## Client-Server Interaction Details

- `register` calls the transport client registration endpoint.
- `poll` sends telemetry heartbeats, processes server commands, sends command results, and starts/stops FRPC based on the heartbeat response.

Traceable references:

- `packages/client/cmd/nixstasis/main.go:20-98`
- `packages/client/cmd/nixstasis/register.go:16-93`
- `packages/client/cmd/nixstasis/poll.go:21-249`
- `packages/client/cmd/nixstasis/script.go:5-12`
