# Client-Server Interface

## Communication Methods

- Go client to Phoenix server:
  - HTTP JSON requests under `/api/v1`.
- Browser to Phoenix LiveView:
  - HTTP for initial requests.
  - LiveView WebSocket transport for stateful UI updates.
- Browser terminal to Phoenix:
  - Phoenix Channels over WebSocket on topic `terminal:*`.
- Caddy to Phoenix:
  - Reverse proxy to `nixstasis:4000`.
  - HTTP ask endpoint for on-demand TLS approval.
- E2E client to Phoenix:
  - HTTP JSON requests under `/e2e`.
- Client FRPC to FRPS:
  - FRP tunnel protocol through configured FRPS ports.

## Go Client to Phoenix Endpoint Mapping

| Go Method | HTTP Endpoint | Server Handler | Purpose |
| --- | --- | --- | --- |
| `RegisterDevice` | `POST /api/v1/devices/register` | `DeviceController.register/2` | Register device and receive UUID |
| `Poll` | `POST /api/v1/devices/:id/heartbeat?api_key=...` | `HeartbeatController.create/2` | Submit telemetry and receive remote-access/command directives |
| `SendCommandResults` | `POST /api/v1/devices/:id/command_results?api_key=...` | `DeviceCommandController.command_results/2` | Acknowledge command execution results |
| `FetchCommandPayload` | `GET /api/v1/devices/:id/command_payloads/:ref?api_key=...` | `DeviceCommandController.command_payload/2` | Fetch deferred command payload |

Traceable references:

- `packages/client/internal/transport/client.go:84-212`
- `packages/server/lib/nixstasis_web/router.ex:58-65`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex:31-37`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex:7-27`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:6-39`

## Request and Response Formats

### Device Registration

Device registration is the credential issuance boundary. The request identifies
the host by MAC address and product metadata; the server may create a pending
device record or update an existing record for the same MAC address. Approved
devices receive a persistent API token in the response. Pending devices do not
receive a token until an operator approves them.

Request:

```json
{
  "mac_address": "00:11:22:33:44:55",
  "product_name": "atom-001122334455",
  "metadata": {
    "ip_address": "192.0.2.10",
    "client_uuid": "optional-existing-uuid"
  }
}
```

Response shape:

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "api_token": "issued-only-after-approval"
  }
}
```

Traceable references:

- `packages/client/internal/transport/client.go:86-120`
- `docs/src/features/go-client-rewrite/design.md`

### Heartbeat

Heartbeat requests authenticate with the registration-issued device API token.
Rate-limited devices receive HTTP `429`. Heartbeats update the server's
`last_seen_at` view of the device, submit telemetry, and return any command or
remote-access directives.

Request:

```json
{
  "telemetry": {},
  "connection_status": {
    "active": true,
    "connection_string": "...",
    "pid": 1234,
    "start_time": "2026-05-06T14:00:00Z"
  }
}
```

Response shape:

```json
{
  "data": {
    "remote_access_token": "shared-frps-token",
    "commands": [
      {
        "command_id": "...",
        "type": "list_scripts",
        "args": [],
        "payload_ref": "..."
      }
    ]
  }
}
```

Traceable references:

- `packages/client/internal/transport/client.go:123-187`
- `docs/src/features/go-client-rewrite/design.md`

### Command Results

Command results are correlated by `command_id`. A heartbeat or command-result
batch that repeats a command identifier should not execute duplicate work; later
duplicates are reported as `FAILED` with a `duplicate_command_id` reason.

Request:

```json
{
  "results": [
    {
      "command_id": "...",
      "status": "OK",
      "output": {}
    }
  ]
}
```

Response shape:

```json
{
  "data": {
    "acknowledged_count": 1
  }
}
```

Traceable references:

- `packages/client/internal/transport/client.go:189-200`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:6-19`
- `docs/src/features/go-client-rewrite/design.md`

### Command Payload

Response shape:

```json
{
  "content_type": "...",
  "name": "...",
  "data": "..."
}
```

Traceable references:

- `packages/client/internal/transport/client.go:202-212`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:28-38`
- `docs/src/features/go-client-rewrite/design.md`

## E2E API Mapping

| Endpoint | Handler | Purpose |
| --- | --- | --- |
| `GET /e2e/suites` | `E2ERunController.suites/2` | List configured suites |
| `GET /e2e/runs` | `E2ERunController.index/2` | List runs |
| `POST /e2e/runs` | `E2ERunController.create/2` | Create or reuse run |
| `GET /e2e/runs/:id` | `E2ERunController.show/2` | Fetch run |
| `POST /e2e/runs/:id/cancel` | `E2ERunController.cancel/2` | Cancel run |
| `GET /e2e/runs/:id/results` | `E2ERunResultController.index/2` | List results |
| `POST /e2e/runs/:id/results` | `E2ERunResultController.create/2` | Submit results |
| `GET /e2e/runs/:id/results/:journey_id/log` | `E2ERunResultController.log/2` | Fetch journey log |

Run creation requires `X-E2E-Protocol-Version`; protocol version `1` is the
default supported version. Legacy `client_version`/`server_version` fields are
not accepted as the version-pairing contract.

Traceable references:

- `packages/server/lib/nixstasis_web/router.ex:68-79`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex:7-93`
- `README.md:96-116`

## Authentication and Session Handling

- Browser routes use Phoenix browser pipeline:
  - `fetch_session`
  - `fetch_live_flash`
  - `protect_from_forgery`
  - `put_secure_browser_headers`
- Supported Compose ingress places Caddy/AuthCrunch in front of Phoenix for public hosts.
- Caddy authorization policy injects headers with claims and validates bearer header according to Caddyfile config.
- Terminal sockets require Phoenix tokens:
  - socket token signed for `terminal_socket`.
  - join payload contains an opaque server-side terminal session ref.
- Runtime device heartbeat, command-result, and command-payload requests require the registration-issued device token as an `api_key` query parameter.
- E2E routes are gated by `NixstasisWeb.Plugs.E2EEnabled`.
- Initial device registration does not attach a device API key because it is the credential issuance step.

Traceable references:

- `packages/server/lib/nixstasis_web/router.ex:4-20`
- `deploy/compose/caddy/Caddyfile:25-38`
- `packages/server/lib/nixstasis_web/channels/user_socket.ex:37-64`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex:20-50`
- `packages/client/internal/transport/client.go:47-54`

## Error Handling Patterns

- Go transport treats any unexpected status as `API returned non-success status: <status>`.
- Go transport allows empty response bodies when a response body target was provided and EOF is returned.
- Runtime device API requests without `api_key` return HTTP `401` with code `missing_api_key`.
- Runtime device API requests with an invalid `api_key` return HTTP `401` with code `invalid_api_key`.
- Heartbeat rejects unapproved devices with HTTP `403` and code `device_not_approved`.
- Command results without a results list return HTTP `400`.
- Command-result processing errors return HTTP `422`.
- Command payload lookup returns HTTP `404` for missing payloads.
- TLS domain denial returns HTTP `401` and `{"error":"The host is not permitted"}`.
- E2E create returns typed error codes in an `error` object.

Traceable references:

- `packages/client/internal/transport/client.go:37-82`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex:16-25`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:15-37`
- `packages/server/lib/nixstasis_web/controllers/tls_controller.ex:21-27`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex:33-62`

## Versioning Strategy

- Device API is documented by this interface page and transport/controller tests.
- E2E API run creation requires protocol version header `X-E2E-Protocol-Version`.
- E2E JSONL logs use schema `e2e_log.v1` according to README.
- Repository tooling currently installs Go `1.26.2` through `mise.toml`; the
  client module target is `go 1.26` in `go.mod`.

Traceable references:

- `docs/src/features/go-client-rewrite/design.md`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex:7-25`
- `README.md:123-135`
- `packages/client/go.mod:1-13`
