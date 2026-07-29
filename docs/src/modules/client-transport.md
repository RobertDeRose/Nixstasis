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
- `docs/src/client-server-interface.md`

## Public Interfaces

- Types:
  - `Client`
  - `PollRequest`
  - `CommandInventoryProbe`
  - `CommandProbe`
  - `CommandInventoryEvidence`
  - `PackageEvidence`
  - `CommandEvidence`
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
  - `(*Client).PollWithInventory`
  - `(*Client).SendCommandResults`
  - `(*Client).FetchCommandPayload`

## Dependencies

### Internal

- `internal/config`
- `internal/frp`
- `internal/identity`
- `internal/inventory`
- `internal/telemetry`

### External

- Go `net/http`
- Go experimental `encoding/json/v2`

## Client-Server Interaction Details

- `RegisterDevice`:
  - `POST {baseURL}/api/v1/devices/register`
  - Sends `mac_address`, optional `product_name`, and optional `metadata`.
  - Expects `201` and response `data.id`.
  - Approved devices receive `data.api_token`; pending devices omit it until approval.
  - Re-registering the same MAC address updates the existing device record rather
    than creating a duplicate identity.
- `Poll`:
  - `POST {baseURL}/api/v1/devices/{uuid}/heartbeat`
  - Sends `telemetry`, `connection_status`, and optional top-level `command_inventory` evidence.
  - Requires the issued device token as `api_key` query parameter.
  - Expects `200` or `202` and optional response `data.remote_access_token`, `data.commands`, and `data.command_inventory_probe`.
  - HTTP `429` indicates the server rate limit rejected the heartbeat.
- `PollWithInventory`:
  - Uses the same heartbeat endpoint as `Poll`.
  - Adds bounded, untrusted inventory evidence collected from the previous server probe.
  - `Poll` is the compatibility wrapper that calls `PollWithInventory` without inventory.
- Inventory collection:
  - Parses selected `/etc/os-release` fields: `ID`, `ID_LIKE`, `VERSION_ID`, and `PRETTY_NAME`.
  - Normalizes architecture names such as `amd64` to `x86_64` and `arm64` to `aarch64`.
  - Detects package managers from known binaries: `apt`, `dnf`, `rpm`, and `nix-env`.
  - Reports package and command evidence only for names present in the server probe.
  - Bounds package and command evidence to 128 entries each and omits relative or non-executable command paths.
- `SendCommandResults`:
  - `POST {baseURL}/api/v1/devices/{uuid}/command_results`
  - Sends `results` array.
  - Requires the issued device token as `api_key` query parameter.
  - Expects `200` or `202`.
- `FetchCommandPayload`:
  - `GET {baseURL}/api/v1/devices/{uuid}/command_payloads/{ref}`
  - Requires the issued device token as `api_key` query parameter.
  - Expects `200` and a `CommandPayload`.

Traceable references:

- `packages/client/internal/transport/client.go`
- `packages/client/internal/inventory/inventory.go`
- `docs/src/client-server-interface.md`
