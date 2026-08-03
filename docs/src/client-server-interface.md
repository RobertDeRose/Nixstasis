# Client-Server Interface

## Communication Methods

- Go client to Phoenix server:
  - HTTP JSON requests under `/api/v1`.
- Builder automation to Phoenix server:
  - Generated Ash JSON:API requests under `/api/json/builder_contract/*`.
  - Legacy compatibility requests under `/api/v1/builder-*`.
- Browser to Phoenix LiveView:
  - HTTP for initial requests.
  - LiveView WebSocket transport for stateful UI updates.
- Browser terminal to Phoenix:
  - Phoenix Channels over WebSocket on topic `terminal:*`.
- Caddy to Phoenix:
  - Reverse proxy to `nixstasis:${PORT}`.
  - HTTP ask endpoint for on-demand TLS approval.
- E2E client to Phoenix:
  - HTTP JSON requests under `/e2e`.
- Client FRPC to FRPS:
  - FRP tunnel protocol through configured FRPS ports.

## Rate Limiting

All `/api/v1` and `/api/json` requests are rate-limited per device (or per
remote IP when no device identity is available).

| Scope                            | Default Limit | Window     |
|----------------------------------|---------------|------------|
| Heartbeat (`POST .../heartbeat`) | 30 requests   | 60 seconds |
| Other API requests               | 120 requests  | 60 seconds |

When the limit is exceeded the server responds with HTTP `429` and body:

```json
{"error": {"code": "rate_limited", "message": "Rate limit exceeded"}}
```

Limits are configurable via application config (`:nixstasis, :rate_limit`
keyword list with `:limit`, `:heartbeat_limit`, and `:window_ms` keys).

Traceable references:

- `packages/server/lib/nixstasis_web/plugs/rate_limiter.ex`
- `packages/server/lib/nixstasis_web/rate_limiter_store.ex`

## Go Client to Phoenix Endpoint Mapping

| Go Method                    | HTTP Endpoint                                               | Server Handler                              | Purpose                                                                                              |
|------------------------------|-------------------------------------------------------------|---------------------------------------------|------------------------------------------------------------------------------------------------------|
| `RegisterDevice`             | `POST /api/v1/devices/register`                             | `DeviceController.register/2`               | Register device and receive UUID                                                                     |
| `Poll` / `PollWithInventory` | `POST /api/v1/devices/:id/heartbeat?api_key=...`            | `HeartbeatController.create/2`              | Submit telemetry and optional command inventory, then receive remote-access/command/probe directives |
| `SendCommandResults`         | `POST /api/v1/devices/:id/command_results?api_key=...`      | `DeviceCommandController.command_results/2` | Acknowledge command execution results                                                                |
| `FetchCommandPayload`        | `GET /api/v1/devices/:id/command_payloads/:ref?api_key=...` | `DeviceCommandController.command_payload/2` | Fetch deferred command payload                                                                       |

Traceable references:

- `packages/client/internal/transport/client.go:84-212`
- `packages/server/lib/nixstasis_web/router.ex:58-65`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex:31-37`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex:7-27`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:6-39`

## Server-managed Stary command contract

The Script Workbench is an operator LiveView workflow, not a public script CRUD API. The
server context queues the existing device command shapes and the Go client continues to use
the `/api/v1` runtime protocol.

### Test and deployment commands

A test command uses `run_script` and executes the supplied `.stary` content without installing
it into the client's normal polling script directory. Deployment uses `install_script` and
the immutable validated version artifact. The common command request shape is:

```json
{
  "command_id": "uuid",
  "type": "run_script",
  "payload": {
    "content_type": "text/x-stary",
    "name": "disk",
    "data": "---\\nname: disk\\n..."
  },
  "payload_ref": "optional-reference"
}
```

Small rendered scripts are sent inline. The server marks scripts larger than 4,096 bytes as
deferred and retains the content behind `payload_ref`. During the poll cycle the Go client:

1. validates the reference;
2. fetches `GET /api/v1/devices/:device_id/command_payloads/:ref?api_key=...`;
3. attaches the response payload to the command; and
4. invokes the serial `run_script` handler.

A missing, invalid, or failed fetch produces a failed command result with a deterministic
`payload_fetch_failed` or `invalid_payload_ref` error and does not execute partial content.
The existing `install_script` deferred-payload behavior remains unchanged.

### Result and authorization boundaries

The client returns one `CommandResult` per command through
`POST /api/v1/devices/:device_id/command_results?api_key=...`. The result output preserves
client status, output, validation details, runtime errors, warnings, and timing when
available. Phoenix authenticates the device token before associating the result with a
script test or deployment run.

The browser operator's trusted device scope is checked by `Nixstasis.Scripts` before any
run or pending command is created. This server-side check is independent of LiveView's
filtered target list. Script audit events identify the trusted operator; result events
identify the authenticated device.

See [Stary Script Workbench operations](operations/script-workbench.md) for workflow and
recovery guidance.

## Device Runtime Ash/OpenAPI Boundary

The Go client continues to use the `/api/v1` mapping above. All five device
runtime actions are now available in the additive generated route family. The
canonical contract for new integrations is:

- `GET /api/json/device_runtime/devices` uses the operator bearer/device-view
  boundary and the device list filters, including `ipv4_address` and
  `connectivity_status`.
- `POST /api/json/device_runtime/devices/register` is the public registration
  action; it does not use a device API key.
- `POST /api/json/device_runtime/devices/:device_id/heartbeat` is the generated
  heartbeat action. It accepts `telemetry`, `connection_status`, and optional
  `command_inventory`, returns `data.commands` plus optional remote-access and
  probe directives with status `200`, and preserves the same orchestration as
  the compatibility endpoint.
- `POST /api/json/device_runtime/devices/:device_id/command_results` accepts
  `results` and returns `data.acknowledged_count` with status `202`; duplicate
  results retain the observed replay/count behavior.
- `GET /api/json/device_runtime/devices/:device_id/command_payloads/:ref`
  returns the raw `{content_type, name, data}` payload with status `200` and
  `404` when the payload is absent.
- Heartbeat, command-result, and deferred-payload actions use `?api_key=...`
  with the generated OpenAPI `deviceApiKey` scheme (`apiKey`, query parameter
  named `api_key`). The device-runtime permission boundary performs lookup and
  authentication before the Ash action; unknown devices are `404`,
  missing/invalid keys are `401`, and unapproved devices are `403`.

Generated action schemas are canonical for Ash consumers and use the Ash
JSON:API media type. The `/api/v1` endpoints remain compatibility wrappers with
the exact JSON envelopes and status codes documented below. Both surfaces share
the same device, monitoring, pending-command, script, and command-policy
orchestration; the generated route must not turn heartbeat or command delivery
into generic CRUD. Heartbeat remains limited to 30 requests per device per
60-second window, while other API routes use the 120-request default.

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
  "schema_definition": {
    "product": "atom-001122334455",
    "version": "v1",
    "type": "object",
    "properties": {
      "temperature_c": {"type": "number"},
      "disk_used_pct": {"type": "number"}
    }
  },
  "metadata": {
    "ip_address": "192.0.2.10",
    "client_uuid": "optional-existing-uuid"
  }
}
```

The request may also carry `ipv4_address` directly; when it is absent, the
server derives it from `metadata.ip_address`. Public registration accepts either
`schema_definition` or the legacy `schema` alias, but the schema must include a
`product` value.

Pending approval response:

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "approval_status": "pending"
  }
}
```

Approved credential response:

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "approval_status": "approved",
    "api_token": "opaque-device-runtime-token"
  }
}
```

Validation error response when the schema payload is missing or invalid:

```json
{
  "errors": {
    "schema_definition": ["schema must include product"]
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
  "telemetry": {
    "scripts": {
      "disk": {
        "data": {
          "usage_pct": 73.2
        }
      }
    }
  },
  "connection_status": {
    "active": true,
    "connection_string": "tcp://frps.example.invalid:7000",
    "pid": 1234,
    "start_time": "2026-05-06T14:00:00Z"
  },
  "command_inventory": {
    "schema_version": 1,
    "probe_catalog_version": "catalog-v1",
    "observed_at": "2026-07-29T12:00:00Z",
    "architecture": "x86_64",
    "package_manager": "apt",
    "os_release": {
      "ID": "ubuntu",
      "ID_LIKE": "debian",
      "VERSION_ID": "24.04",
      "PRETTY_NAME": "Ubuntu 24.04 LTS"
    },
    "packages": {
      "coreutils": {"installed": true}
    },
    "commands": {
      "df": {"path": "/usr/bin/df"}
    }
  }
}
```

`command_inventory` is optional, top-level, and untrusted. The client only
reports package names and command names from the latest server
`command_inventory_probe`; the data is evidence for server compatibility checks
and never grants client-side permissions by itself.

No-command response with an inventory probe:

```json
{
  "data": {
    "commands": [],
    "command_inventory_probe": {
      "catalog_version": "catalog-v1",
      "package_names": ["coreutils"],
      "command_probes": [
        {
          "name": "df",
          "os_family": "debian",
          "package_name": "coreutils",
          "command_path": "/usr/bin/df"
        }
      ]
    }
  }
}
```

Clients cache the probe and send matching inventory on a later heartbeat. If the
probe is absent, clients omit `command_inventory`.

Remote-access response:

```json
{
  "data": {
    "remote_access_token": "shared-frps-token",
    "commands": []
  }
}
```

Command delivery response:

```json
{
  "data": {
    "commands": [
      {
        "command_id": "11111111-1111-4111-8111-111111111111",
        "type": "install_script",
        "args": [],
        "payload": {
          "name": "disk",
          "data": "# Starlark script content"
        }
      }
    ]
  }
}
```

Deferred payload response:

```json
{
  "data": {
    "commands": [
      {
        "command_id": "22222222-2222-4222-8222-222222222222",
        "type": "install_script",
        "args": [],
        "payload_ref": "install-disk-v2"
      }
    ]
  }
}
```

Authentication failures use the shared runtime API error envelope:

```json
{
  "error": {
    "code": "invalid_api_key",
    "message": "API key is invalid"
  }
}
```

Devices that are not approved receive a distinct authorization failure:

```json
{
  "error": {
    "code": "device_not_approved",
    "message": "Device is not approved"
  }
}
```

Traceable references:

- `packages/client/internal/transport/client.go:123-232`
- `packages/client/internal/inventory/inventory.go`
- `docs/src/features/go-client-rewrite/design.md`

### Command Results

Command results are correlated by `command_id`. The server acknowledges results
that match pending commands for the authenticated device and ignores unknown or
non-matching command identifiers.

Request:

```json
{
  "results": [
    {
      "command_id": "11111111-1111-4111-8111-111111111111",
      "status": "OK",
      "output": {"installed": true}
    },
    {
      "command_id": "33333333-3333-4333-8333-333333333333",
      "status": "FAILED",
      "error": "script validation failed"
    }
  ]
}
```

Accepted response:

```json
{
  "data": {
    "acknowledged_count": 2
  }
}
```

Missing-token response:

```json
{
  "error": {
    "code": "missing_api_key",
    "message": "API key is required"
  }
}
```

Traceable references:

- `packages/client/internal/transport/client.go:189-200`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:6-19`
- `docs/src/features/go-client-rewrite/design.md`

### Command Payload

Success response:

```json
{
  "content_type": "text/plain",
  "name": "disk",
  "data": "# Starlark script content"
}
```

Missing payload response:

```json
{
  "error": {
    "code": "payload_not_found",
    "message": "Command payload not found"
  }
}
```

Wrong-device or invalid-token response:

```json
{
  "error": {
    "code": "invalid_api_key",
    "message": "API key is invalid"
  }
}
```

### Caddy Domain Approval

The Caddy on-demand TLS ask endpoint uses the `domain` query parameter. It
returns HTTP `204` with an empty body when the host is permitted.

Allowed reserved host example:

```http
GET /api/v1/check_domain?domain=nixstasis.devices.example.com
```

Allowed remote-access-requesting device host example:

```http
GET /api/v1/check_domain?domain=atom-aabbccddeeff.devices.example.com
```

Denied host response:

```json
{
  "error": "The host is not permitted"
}
```

Traceable references:

- `packages/server/lib/nixstasis_web/controllers/tls_controller.ex:8-17`
- `deploy/compose/caddy/Caddyfile:42-75`
- `docs/src/runtime-boundaries.md`
- `docs/src/modules/deployment-compose.md`

## Builder API Mapping

| Endpoint                                                                             | Handler                                          | Purpose                                                    |
|--------------------------------------------------------------------------------------|--------------------------------------------------|------------------------------------------------------------|
| `GET /api/json/builder_contract/schema_references`                                   | `BuilderContract.list_schema_references`         | Generated Ash action contract for schema references        |
| `GET /api/json/builder_contract/schemas/:schema_id/versions/:schema_version/options` | `BuilderContract.options_for`                    | Generated Ash action contract for normalized options       |
| `POST /api/json/builder_contract/builder_configurations/validate`                    | `BuilderContract.validate_builder_configuration` | Generated Ash action contract for selection validation     |
| `GET /api/v1/builder-schemas`                                                        | `BuilderSchemaController.index/2`                | Legacy JSON compatibility wrapper for schema references    |
| `GET /api/v1/builder-schemas/:schema_id/versions/:schema_version/options`            | `BuilderSchemaController.options/2`              | Legacy JSON compatibility wrapper for normalized options   |
| `POST /api/v1/builder-configurations/validate`                                       | `BuilderConfigValidationController.create/2`     | Legacy JSON compatibility wrapper for selection validation |

Generated builder action contracts are documented in
`packages/server/priv/static/openapi.yaml`. The `/api/v1` builder routes remain
documented by `docs/src/reference/openapi/builder-api.yaml` until existing
consumers migrate to the generated JSON:API surface.

Traceable references:

- `packages/server/lib/nixstasis/schema_options/builder_contract.ex`
- `packages/server/lib/nixstasis_web/controllers/builder_schema_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/builder_config_validation_controller.ex`

## Builder API Examples

The schema examples below are for the legacy `/api/v1` compatibility wrapper and
use its `application/json` envelope. The generated `/api/json` options action
returns the same domain fields as a raw action payload, uses JSON:API errors, and
is protected by the generated API permission pipeline. The validation request and
result fields are shared by both surfaces, while their route/status/error
contracts remain distinct.

### Builder Route Contract Matrix

| Surface                        | Authorization                                                                    | Success                                             | Errors                                         |
|--------------------------------|----------------------------------------------------------------------------------|-----------------------------------------------------|------------------------------------------------|
| `/api/json/builder_contract/*` | Bearer/report-view through `JsonApiPermissions`                                  | Raw action payloads; validation returns `201`       | JSON:API `400`, `403`, and `404` as applicable |
| `/api/v1/builder-*`            | Compatibility `:api` pipeline and rate limiter; deployment-edge auth is separate | Legacy `application/json`; validation returns `200` | Legacy `404`/`422` error envelopes             |

Use the generated routes for the canonical Ash/OpenAPI contract. Use the
compatibility wrappers when an existing client requires the legacy envelope,
status, or error shape.

### Legacy `/api/v1` schema option response

Schema option lookup response:

```json
{
  "data": {
    "schema_id": "thermostat-v1",
    "schema_version": "v1",
    "builder": "alert",
    "options": [
      {
        "key": "temp",
        "label": "temp",
        "value_type": "number",
        "order_index": 0,
        "selectable": true
      }
    ],
    "load_time_ms": 4
  }
}
```

Missing schema response:

```json
{
  "error": {
    "code": "schema_not_found",
    "message": "Schema reference not found"
  }
}
```

### Shared validation payload

Validation request:

```json
{
  "builder": "report",
  "schema_id": "sensor-v2",
  "schema_version": "v2",
  "selections": [
    {"slot_id": "a", "selected_key": "pressure"},
    {"slot_id": "b", "selected_key": "missing"}
  ]
}
```

Validation response with stale selections cleared:

```json
{
  "valid": false,
  "issues": [
    {
      "issue_code": "invalid_schema_field",
      "message": "Selected field is not available in the active schema.",
      "slot_id": "b",
      "blocking": true
    }
  ],
  "cleared_slot_ids": ["b"]
}
```

Validation success response:

```json
{
  "valid": true,
  "issues": [],
  "cleared_slot_ids": []
}
```

Traceable references:

- `docs/src/reference/openapi/builder-api.yaml`
- `packages/server/test/nixstasis_web/controllers/builder_schema_controller_test.exs`
- `packages/server/test/nixstasis_web/controllers/builder_config_validation_controller_test.exs`

## E2E API Mapping

| Endpoint                                    | Handler                           | Purpose                |
|---------------------------------------------|-----------------------------------|------------------------|
| `GET /e2e/suites`                           | `E2ERunController.suites/2`       | List configured suites |
| `GET /e2e/runs`                             | `E2ERunController.index/2`        | List runs              |
| `POST /e2e/runs`                            | `E2ERunController.create/2`       | Create or reuse run    |
| `GET /e2e/runs/:id`                         | `E2ERunController.show/2`         | Fetch run              |
| `POST /e2e/runs/:id/cancel`                 | `E2ERunController.cancel/2`       | Cancel run             |
| `GET /e2e/runs/:id/results`                 | `E2ERunResultController.index/2`  | List results           |
| `POST /e2e/runs/:id/results`                | `E2ERunResultController.create/2` | Submit results         |
| `GET /e2e/runs/:id/results/:journey_id/log` | `E2ERunResultController.log/2`    | Fetch journey log      |

Run creation requires `X-E2E-Protocol-Version`; protocol version `1` is the
default supported version. Legacy `client_version`/`server_version` fields are
not accepted as the version-pairing contract.

Traceable references:

- `packages/server/lib/nixstasis_web/router.ex:68-79`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex:7-93`
- `README.md:96-116`

## E2E API Examples

Run creation request:

```http
POST /e2e/runs
X-E2E-Protocol-Version: 1
Content-Type: application/json
```

```json
{
  "suite_id": "full",
  "environment_label": "local",
  "trigger_source": "manual",
  "metadata": {"requested_by": "operator@example.invalid"}
}
```

Run creation response:

```json
{
  "data": {
    "id": "44444444-4444-4444-8444-444444444444",
    "suite_id": "full",
    "journey_ids": ["auth", "dashboard"],
    "environment_label": "local",
    "trigger_source": "manual",
    "protocol_version": "1",
    "status": "queued"
  }
}
```

Idempotent run reuse uses the same request with an `idempotency_key` that
matches an existing run:

```json
{
  "suite_id": "full",
  "environment_label": "local",
  "trigger_source": "ci",
  "idempotency_key": "ci-2026-05-30T120000Z"
}
```

Idempotent reuse response returns the existing run through the same success
response path:

```json
{
  "data": {
    "id": "44444444-4444-4444-8444-444444444444",
    "suite_id": "full",
    "journey_ids": ["auth", "dashboard"],
    "environment_label": "local",
    "trigger_source": "ci",
    "protocol_version": "1",
    "status": "queued"
  }
}
```

Environment lock conflict response:

```json
{
  "error": {
    "code": "environment_locked",
    "message": "Environment 'local' already has an active E2E run."
  }
}
```

Protocol mismatch response:

```json
{
  "error": {
    "code": "protocol_mismatch",
    "message": "Unsupported protocol version '99'."
  }
}
```

Seed failure response:

```json
{
  "error": {
    "code": "seed_failed",
    "message": "Baseline test data is missing. Seed script not found for environment 'local'."
  }
}
```

Cancellation response:

```json
{
  "data": {
    "id": "44444444-4444-4444-8444-444444444444",
    "status": "cancelled"
  }
}
```

Result submission request:

```json
{
  "results": [
    {
      "journey_id": "auth",
      "status": "passed",
      "duration_ms": 1200,
      "log_ref": "runs/44444444-4444-4444-8444-444444444444/auth.jsonl"
    }
  ]
}
```

Result submission response:

```json
{
  "data": [
    {
      "journey_id": "auth",
      "status": "passed",
      "duration_ms": 1200,
      "log_ref": "runs/44444444-4444-4444-8444-444444444444/auth.jsonl"
    }
  ]
}
```

Journey log response:

```json
{
  "data": {
    "run_id": "44444444-4444-4444-8444-444444444444",
    "journey_id": "auth",
    "content": "{\"status\":\"ok\"}\n"
  }
}
```

Missing or pruned log response:

```json
{
  "error": {
    "code": "log_unavailable",
    "message": "Log is unavailable (possibly pruned or deleted)."
  }
}
```

Traceable references:

- `docs/src/reference/openapi/e2e-api.yaml`
- `packages/server/test/nixstasis_web/controllers/e2e_run_controller_test.exs`
- `packages/server/test/nixstasis_web/controllers/e2e_run_result_controller_test.exs`

## Report And Alert API Examples

Custom report result preview response:

```json
{
  "data": {
    "fields": ["device_id", "temperature_c", "created_at"],
    "rows": [
      {
        "device_id": "550e8400-e29b-41d4-a716-446655440000",
        "temperature_c": 21.5,
        "created_at": "2026-05-06T14:00:00Z"
      }
    ]
  }
}
```

Missing report response uses HTTP `404` with an empty body.

Alert-rule HTTP contracts are generated with the Ash JSON:API OpenAPI document,
not retained as bespoke `/api/v1` examples. Use
`packages/server/priv/static/openapi.yaml` paths under `/api/json/alert_rules`
for the canonical alert-rule request and response shapes.

Traceable references:

- `docs/src/reference/openapi/report-api.yaml`
- `packages/server/lib/nixstasis_web/controllers/report_result_controller.ex`
- `packages/server/priv/static/openapi.yaml`

## Authentication and Session Handling

- Browser routes use Phoenix browser pipeline:
  - `fetch_session`
  - `fetch_live_flash`
  - `protect_from_forgery`
  - `put_secure_browser_headers`
- Supported Compose ingress places Caddy/AuthCrunch in front of Phoenix for public hosts.
- Caddy authorization policy injects headers with claims and validates bearer header according to Caddyfile config.
- The high-level split between browser, device, Caddy, Ash JSON:API, and E2E
  API surfaces is summarized in [Architecture Overview](architecture.md).
- Terminal sockets require Phoenix tokens:
  - the `terminal_socket` token is exposed only after the matching
    `ssh_authorize` command result is `OK`;
  - join payloads contain an opaque server-side terminal session ref and the
    non-empty matching `command_id`;
  - the channel revalidates device ownership, command type, versioned content
    type, and `payload.name`/`data.session_ref` binding.
- Device heartbeat commands use the exact dynamic SSH contracts:
  - `ssh_authorize` has top-level `public_key` and a versioned payload targeting
    `nixstasis-support` with positive TTL and session ref;
  - `ssh_revoke` has versioned payload content type
    `application/vnd.nixstasis.ssh-revoke+json;version=1` and matching session
    ref, and is an idempotent best-effort cleanup command.
- The client and installed OpenSSH helper use the fixed local socket
  `/run/nixstasis/ssh-authority.sock`; no browser-terminal key is persisted in
  an `authorized_keys` file. See [API & Runtime Contracts](reference/contracts.md#browser-terminal-ssh-authorization-contract)
  for the complete command payloads.
- Runtime device heartbeat, command-result, and command-payload requests require the registration-issued device token as an `api_key` query parameter.
- `apply_command_policy` uses the same heartbeat + optional command-payload-ref transport as other runtime commands; clients persist the accepted policy outside the script directory and use it to override local `runtime.exec_commands` until a newer server policy replaces it.
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
- Command results without a results list return HTTP `400`; the current list-input
  controller path has no reachable `422` processing-error branch.
- Generated device action routes use explicit JSON:API validation/error documents;
  that generated contract does not change the `/api/v1` wrapper behavior.
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
