# Client Transport

## Language

- Go.

## Runtime Context

- Client HTTP boundary to Phoenix.

## Purpose

- Encapsulates JSON HTTP requests for device registration, heartbeat polling, command-result submission, and deferred command-payload retrieval.

## Key Files

- `packages/client/internal/transport/client.go`
- `packages/client/internal/transport/register_test.go`
- `packages/client/internal/transport/client_runtime_test.go`
- `specs/004-rewrite-client-go/contracts/device-api.yaml`

## Public Interfaces

- Types:
  - `Client`
  - `PollRequest`
  - `CommandStatus`
  - `CommandRequest`
  - `CommandPayload`
  - `CommandResult`
  - `PollResponse`
  - `CommandResultsRequest`
- Constants:
  - `CommandStatusOK`
  - `CommandStatusFailed`
- Functions and methods:
  - `NewClient`
  - `(*Client).RegisterDevice`
  - `(*Client).Poll`
  - `(*Client).SendCommandResults`
  - `(*Client).FetchCommandPayload`

## Dependencies

### Internal

- `internal/config`
- `internal/frp`
- `internal/identity`
- `internal/telemetry`

### External

- Go `net/http`
- Go experimental `encoding/json/v2`

## Client-Server Interaction Details

- `RegisterDevice`:
  - `POST {baseURL}/api/v1/devices/register`
  - Sends `mac_address`, optional `product_name`, and optional `metadata`.
  - Expects `201` and response `data.id`.
- `Poll`:
  - `POST {baseURL}/api/v1/devices/{uuid}/heartbeat`
  - Sends `telemetry` and `connection_status`.
  - Expects `200` or `202` and response `data.remote_access_requested` plus optional `data.commands`.
- `SendCommandResults`:
  - `POST {baseURL}/api/v1/devices/{uuid}/command_results`
  - Sends `results` array.
  - Expects `200` or `202`.
- `FetchCommandPayload`:
  - `GET {baseURL}/api/v1/devices/{uuid}/command_payloads/{ref}`
  - Expects `200` and a `CommandPayload`.

Traceable references:
- `packages/client/internal/transport/client.go:21-212`
- `specs/004-rewrite-client-go/contracts/device-api.yaml:7-170`
