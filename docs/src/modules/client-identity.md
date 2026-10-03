# Client Identity

## Language

- Go.

## Runtime Context

- Client local host identity detection and persistence.

## Purpose

- Detects primary MAC/IP identity, generates device names, persists
  server-assigned runtime credentials, and loads those credentials for polling.

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
  - `Credentials`
  - `Store`
- Functions and methods:
  - `GetPrimaryMAC`
  - `GetPrimaryIP`
  - `GenerateDeviceName`
  - `NewStore`
  - `(*Store).Load`
  - `(*Store).LoadUUID`
  - `(*Store).Save`
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
- Initial pending registration responses include a one-time registration token.
  The client stores the UUID and proof at `config.RegistrationPath()` with
  owner-only permissions so systemd retries and reboots can resume enrollment.
- After approval, the client presents that proof to the registration endpoint.
  The server rotates it into the runtime API token; the client then stores UUID
  and runtime token together as JSON at `config.IdentityPath()` and removes the
  temporary registration state.
- Legacy identity files that contain only a UUID are still readable, but runtime
  heartbeat, command-result, and command-payload requests require the stored API
  token once the device is approved. Existing approved records without a valid
  registration/runtime proof cannot recover credentials through public
  re-registration.
- `poll` loads stored credentials from `/etc/nixstasis/id` via
  `config.IdentityPath()` before sending heartbeat requests.

Traceable references:

- `packages/client/cmd/nixstasis/register.go:28-93`
- `packages/client/cmd/nixstasis/poll.go:38-47`
- `packages/client/internal/identity/store.go:18-157`
- `packages/client/internal/config/config.go:116-119`
