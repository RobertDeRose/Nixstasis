# Client Identity

## Language

- Go.

## Runtime Context

- Client local host identity detection and persistence.

## Purpose

- Detects primary MAC/IP identity, generates device names, persists server-assigned UUIDs, and loads UUIDs for polling.

## Key Files

- `packages/client/internal/identity/types.go`
- `packages/client/internal/identity/detect.go`
- `packages/client/internal/identity/store.go`
- `packages/client/internal/identity/detect_test.go`
- `packages/client/internal/identity/store_test.go`
- `packages/client/cmd/nixstasis/register.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/internal/config/config.go`

## Public Interfaces

- Types:
  - `DeviceIdentity`
  - `Store`
- Functions and methods:
  - `GetPrimaryMAC`
  - `GetPrimaryIP`
  - `GenerateDeviceName`
  - `NewStore`
  - `(*Store).LoadUUID`
  - `(*Store).SaveUUID`
  - `config.IdentityPath`

## Dependencies

### Internal

- `internal/config`
- `internal/transport`

### External

- Go standard library networking and filesystem APIs.

## Client-Server Interaction Details

- `register` detects MAC/IP and sends identity data to `POST /api/v1/devices/register`.
- `poll` loads the stored UUID from `/etc/nixstasis/id` via `config.IdentityPath()` before sending heartbeat requests.

Traceable references:
- `packages/client/cmd/nixstasis/register.go:28-93`
- `packages/client/cmd/nixstasis/poll.go:38-47`
- `packages/client/internal/config/config.go:116-119`
