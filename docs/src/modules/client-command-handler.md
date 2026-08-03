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
- `packages/client/internal/commandpolicy/store.go`
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
- Supported command types are `list_scripts`, `run_script`, `install_script`,
  `remove_script`, `ssh_authorize`, `ssh_revoke`, and `apply_command_policy`.
- `run_script` executes a supplied Stary artifact for a test without installing it into the
  normal polling script directory. It is serialized with install/remove and other
  filesystem-affecting commands.
- `ssh_authorize` validates the exact versioned payload, target user, session
  binding, TTL, and public key before storing it in the in-memory SSH authority;
  `ssh_revoke` removes the matching session ref as an idempotent no-op when it is
  already absent. Neither command writes browser-terminal keys to disk.
- Commands with deferred payload references are hydrated through `FetchCommandPayload` in
  the poll loop before execution. A failed or invalid hydration produces a failed command
  result and the command handler is not invoked with incomplete content.
- `apply_command_policy` succeeds only after the client updates runtime config and durably writes the persisted server policy outside the script directory.
- Results are sent to `POST /api/v1/devices/:device_id/command_results`.
- `run_script` uses `text/x-stary` (or the compatibility `text/stary`) payload content types,
  preserves client validation/runtime output, and is bounded by the handler's five-second
  command timeout.

Traceable references:

- `packages/client/internal/commands/handler.go:17-230`
- `packages/client/cmd/nixstasis/poll.go:198-249`
- `packages/client/internal/transport/client.go:140-212`
