# Client Command Handler

## Language

- Go.

## Runtime Context

- Client server-command execution.

## Purpose

- Executes supported commands returned by the server in heartbeat responses and produces command result payloads.

## Key Files

- `packages/client/internal/commands/handler.go`
- `packages/client/internal/commands/fs.go`
- `packages/client/internal/commands/handler_test.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/internal/transport/client.go`

## Public Interfaces

- Types:
  - `Handler`
- Functions and methods:
  - `NewHandler`
  - `(*Handler).ExecuteBatch`

## Dependencies

### Internal

- `internal/script`
- `internal/transport`

### External

- Go `context`
- Go `sync`
- Go filesystem APIs.

## Client-Server Interaction Details

- Commands originate in `PollResponse.Commands` from `POST /api/v1/devices/:device_id/heartbeat`.
- Supported command types:
  - `list_scripts`
  - `install_script`
  - `remove_script`
- Commands with deferred payload references are hydrated through `FetchCommandPayload` before execution.
- Results are sent to `POST /api/v1/devices/:device_id/command_results`.

Traceable references:
- `packages/client/internal/commands/handler.go:17-230`
- `packages/client/cmd/nixstasis/poll.go:198-249`
- `packages/client/internal/transport/client.go:140-212`
