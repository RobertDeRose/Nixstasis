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
  - `DeviceCredentials`
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
  - `config.RouteProfileSelection`
  - `CommandResultsRequest`
- Constants:
  - `CommandStatusOK`
  - `CommandStatusFailed`
- Functions and methods:
  - `NewClient`
  - `(*Client).RegisterDevice`
  - `(*Client).RegisterDeviceCredentials`
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

- `RegisterDeviceCredentials` (and the UUID-only `RegisterDevice` wrapper):
  - `POST {baseURL}/api/v1/devices/register`
  - Sends `mac_address`, product/schema data, optional `metadata`, and the
    caller's durably saved `registration_token` and proposed `replacement_token`.
  - Expects `201` and response `data.id`.
  - Pending devices return an enrollment proof, omit `data.api_token`, and yield
    `ErrDevicePendingApproval`. Approved exchange returns the proposed runtime
    token as `data.api_token`; identical committed retries do not rotate it again.
  - Re-registering the same MAC address updates the existing device record rather
    than creating a duplicate identity.
- `Poll`, `PollWithInventory`, and `PollWithInventoryAndHostKey`:
  - `POST {baseURL}/api/v1/devices/{uuid}/heartbeat`
  - All variants send `telemetry` and `connection_status`.
  - `Poll` omits `command_inventory` and `ssh_host_key`; `PollWithInventory` adds
    optional top-level `command_inventory` evidence but still omits `ssh_host_key`.
  - `PollWithInventoryAndHostKey` also sends the local sshd host public key as
    `ssh_host_key`. The CLI poll loop calls this variant directly, so only it enrolls
    or refreshes host identity; an empty key is omitted.
  - The CLI reads only the Ed25519 host key at `/etc/ssh/ssh_host_ed25519_key.pub`;
    the heartbeat omits `ssh_host_key` when that file is missing or malformed. RSA and
    ECDSA host keys are not reported.
  - Requires the issued device token as `Authorization: Bearer <device-token>`; the token is never added to the URL.
  - Expects `200` or `202` and optional response `data.remote_access_token`,
    `data.remote_access_expires_at_ms`, `data.remote_access_lease_id`,
    `data.remote_access_profile`, `data.commands`, and
    `data.command_inventory_probe`.
  - `remote_access_profile` is only a named/versioned reference; the client
    resolves it against local configuration and rejects unknown or unsafe routes.
  - HTTP `413` indicates normalized telemetry exceeded the server persistence
    limits; the heartbeat is rejected before device or monitoring state changes.
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
  - Requires the issued device token as `Authorization: Bearer <device-token>`; the token is never added to the URL.
  - Expects `200` or `202`.
- `FetchCommandPayload`:
  - `GET {baseURL}/api/v1/devices/{uuid}/command_payloads/{ref}`
  - Requires the issued device token as `Authorization: Bearer <device-token>`; the token is never added to the URL.
  - Expects `200` and a `CommandPayload`.

Traceable references:

- `packages/client/internal/transport/client.go`
- `packages/client/internal/inventory/inventory.go`
- `docs/src/client-server-interface.md`
