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
| `Poll` | `POST /api/v1/devices/:id/heartbeat` | `HeartbeatController.create/2` | Submit telemetry and receive remote-access/command directives |
| `SendCommandResults` | `POST /api/v1/devices/:id/command_results` | `DeviceCommandController.command_results/2` | Acknowledge command execution results |
| `FetchCommandPayload` | `GET /api/v1/devices/:id/command_payloads/:ref` | `DeviceCommandController.command_payload/2` | Fetch deferred command payload |

Traceable references:
- `packages/client/internal/transport/client.go:84-212`
- `packages/server/lib/nixstasis_web/router.ex:58-65`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex:31-37`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex:7-27`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:6-39`

## Request and Response Formats

### Device Registration

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
    "id": "550e8400-e29b-41d4-a716-446655440000"
  }
}
```

Traceable references:
- `packages/client/internal/transport/client.go:86-120`
- `specs/004-rewrite-client-go/contracts/device-api.yaml:8-42`

### Heartbeat

Request:

```json
{
  "telemetry": {},
  "connection_status": {
    "connected": true,
    "connection_string": "..."
  }
}
```

Response shape:

```json
{
  "data": {
    "remote_access_requested": true,
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
- `specs/004-rewrite-client-go/contracts/device-api.yaml:43-106`

### Command Results

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
- `specs/004-rewrite-client-go/contracts/device-api.yaml:107-141`

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
- `specs/004-rewrite-client-go/contracts/device-api.yaml:142-170`

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

Run creation requires `X-E2E-Protocol-Version`.

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
  - join token signed for `terminal_session`.
- E2E routes are gated by `NixstasisWeb.Plugs.E2EEnabled`.
- Device API calls in observed Go transport do not attach an application auth header.

Traceable references:
- `packages/server/lib/nixstasis_web/router.ex:4-20`
- `deploy/compose/caddy/Caddyfile:25-38`
- `packages/server/lib/nixstasis_web/channels/user_socket.ex:37-64`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex:20-50`
- `packages/client/internal/transport/client.go:47-54`

## Error Handling Patterns

- Go transport treats any unexpected status as `API returned non-success status: <status>`.
- Go transport allows empty response bodies when a response body target was provided and EOF is returned.
- Heartbeat rejects unapproved devices with HTTP `403` and `{"error":"Device not approved"}`.
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

- Device API contract document declares OpenAPI `version: 1.0.0`.
- E2E API run creation requires protocol version header `X-E2E-Protocol-Version`.
- E2E JSONL logs use schema `e2e_log.v1` according to README.
- Client Go module declares `go 1.25.4` in `go.mod`.

Traceable references:
- `specs/004-rewrite-client-go/contracts/device-api.yaml:1-5`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex:7-25`
- `README.md:123-135`
- `packages/client/go.mod:1-13`
