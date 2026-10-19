# Client-Server Interface

How clients talk to the server over HTTP: which routes each client uses, how they authenticate, rate limits, error
formats, versioning, and worked examples of requests and responses. The test harness's routes are covered separately,
in [E2E API](development/e2e/api.md). The exact schemas are in the
[OpenAPI Contracts](reference/openapi/index.md), and how the pieces fit together is in the
[Architecture Overview](architecture.md).

## AtomixOS Bootstrap Provisioning

Operators upload an initial-boot artifact with `POST /api/v1/provisioning/devices/:device_id` as
`application/octet-stream`, then read or withdraw the delivery under `/api/v1/provisioning/deliveries/:id`. The
delivery, retry, and idempotency rules are owned by [Server Provisioning](modules/server-provisioning.md).

## Rate Limiting

Requests are limited in two stages. Before authentication, Phoenix counts requests per route and per network origin.
After authentication, each device gets its own quotas.

In the supported deployment, Caddy sets the internal `X-Nixstasis-Client-IP` header to the real client address, and
Phoenix trusts that header only when the request also carries Caddy's proxy credential. Anyone calling Phoenix directly
is counted by their own socket address. A device ID from the request is never used for counting before
authentication, because anyone could make one up.

| Scope                                     | Default Limit   | Window     |
|-------------------------------------------|-----------------|------------|
| Pre-auth origin + route                   | 1,000 requests  | 60 seconds |
| Pre-auth global flood ceiling             | 50,000 requests | 60 seconds |
| Authenticated heartbeat per device        | 30 requests     | 60 seconds |
| Other authenticated device runtime action | 120 requests    | 60 seconds |

A few details keep the limits fair and hard to dodge:

- The per-origin quota is checked before the global ceiling, so one noisy origin cannot use up everyone else's share.
- Phoenix tracks at most 4,096 origins at once. When it is full, it clears expired entries before refusing a new
  origin.
- IPv6 addresses share a quota per /64 prefix. An IPv4 address written in IPv6 form (`::ffff:a.b.c.d`) counts as that
  IPv4 address, so different spellings of one address cannot get extra quota.
- Heartbeats, command results, and payload fetches each have their own authenticated quota. Requests with a bad token
  never touch a device's quota, and one kind of request cannot use up another's.

Over the limit, the `/api/v1` routes answer HTTP `429` with:

```json
{"error": {"code": "rate_limited", "message": "Rate limit exceeded"}}
```

The JSON:API routes under `/api/json` use the JSON:API `errors` format, with content type `application/vnd.api+json`,
for every limit:

```json
{"errors": [{"code": "rate_limited", "detail": "Rate limit exceeded"}]}
```

The limits are set in application config under `:nixstasis, :rate_limit`, with the keys `:preauth_limit`,
`:preauth_global_limit`, `:preauth_max_keys`, `:device_limit`, `:heartbeat_limit`, and `:window_ms`.

## Client Routes

The client uses only the `/api/v1` device routes; the method-to-route mapping is in
[Client Transport](modules/client-transport.md).

## Server-managed Stary command contract

The Script Workbench is part of the web UI; there is no public API for managing scripts. It sends devices the same
commands as everything else, over the normal `/api/v1` protocol.

### Test and deployment commands

A test sends `run_script`, which runs the `.stary` content once without installing it. A deployment sends
`install_script` with the fixed, validated version. Both commands look like this:

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

Scripts up to 4,096 bytes are sent inside the command. For anything larger, the server keeps the content and sends a
`payload_ref` instead. A script whose encoded payload is over 1 MiB, the most a client will download, is refused when
it is queued, so every queued script can be fetched. For a deferred payload, the client:

1. checks the reference;
2. fetches `GET /api/v1/devices/:device_id/command_payloads/:ref` with `Authorization: Bearer <device-token>`;
3. attaches the payload to the command;
4. runs it with the `run_script` handler, one at a time.

If the fetch fails or the reference is invalid, the command fails with `payload_fetch_failed` or
`invalid_payload_ref`, and nothing partial runs. `install_script` handles deferred payloads the same way.

### Result and authorization boundaries

The client sends one `CommandResult` per command to `POST /api/v1/devices/:device_id/command_results` with
`Authorization: Bearer <device-token>`. Each result carries the client's status and output, plus any validation
details, runtime errors, warnings, and timing. Phoenix checks the device token before attaching the result to a test or
deployment.

Before any run or command is created, `Nixstasis.Scripts` checks every target against the operator's device scope. It
does this itself, regardless of what the page showed. Audit events for runs name the operator; events for results name
the device.

The operator workflow and troubleshooting are in [Stary Script Workbench](operations/script-workbench.md).

## Device API Routes

The client uses the `/api/v1` routes described in the rest of this page. Every device action is also available as a
generated JSON:API route under `/api/json/device_runtime/devices`, for tools that work with Ash's JSON:API:

- **List devices:** `GET /api/json/device_runtime/devices`, or `GET /api/v1/devices`. Both need a
  verified operator with permission to view devices. Both apply the operator's device scope, as decided by Phoenix,
  before any filters such as `ipv4_address` and `connectivity_status`, and both ignore forwarded device-scope headers.
  The `/api/v1` route answers `401` with an empty body for missing or invalid sign-in, and `403` without permission. The
  local-development fallback still works.
- **Register:** `POST /api/json/device_runtime/devices/register`. Registration is public and uses no device token.
- **Heartbeat:** `POST /api/json/device_runtime/devices/:device_id/heartbeat` accepts `telemetry`, `connection_status`,
  `ssh_host_key`, and an optional `command_inventory`. It answers `200` with `data.commands` and, when they apply, a
  remote-access token and profile and an inventory probe. It does exactly what the `/api/v1` heartbeat does.
- **Command results:** `POST /api/json/device_runtime/devices/:device_id/command_results` accepts `results` and answers
  `202` with `data.acknowledged_count`. Duplicate results are counted the same way as on `/api/v1`.
- **Command payload:** `GET /api/json/device_runtime/devices/:device_id/command_payloads/:ref` answers `200` with the
  raw `{content_type, name, data}` payload, or `404` if there is none.

The heartbeat, command-result, and payload routes take `Authorization: Bearer <device-token>`, described in the OpenAPI
document as the `deviceBearer` scheme. A token in the query string is rejected. The device is looked up and
authenticated before the action runs: an unknown device gets `404`, a missing or invalid token `401`, and an unapproved
device `403`.

The generated routes use the JSON:API media type, and their schemas are in the generated OpenAPI file. The `/api/v1`
routes use the plain JSON formats and status codes shown below. Both sets of routes run the same code for
devices, monitoring, commands, scripts, and command policies, so a heartbeat is never reduced to a plain database
update. Heartbeats are limited to 30 per device per 60 seconds; other API routes allow 120.

## Request and Response Formats

### Device Registration

Registration is how a device gets its credentials. A device identifies itself by MAC address and product details, and
proves who it is with secrets it generated itself.

**First request.** Before contacting the server, the client generates a `registration_token`: 32 random bytes, encoded
as 43 characters of unpadded base64url, and saves it. The server creates a pending device and stores only a hash of
the token. A pending device gets no runtime token, and its registration token cannot be used for anything else.

**After approval.** Every later registration from the same MAC must include the saved token, or the current runtime
token, as `registration_token`. Once the device is approved, the client also generates and saves a second secret in
the same format, the `replacement_token`, before sending. In one transaction, the server checks the current token,
updates the device's own details, and swaps in the new secret. The response's `api_token` is that
`replacement_token`, and the old registration token stops working.

**Retries.** Keep both secrets unchanged across retries and restarts. If the response to a successful exchange is
lost, sending the same `replacement_token` again returns the same `api_token`, without changing anything. The old
registration token alone is not enough. Once the device has rotated again, the previous replacement no longer works.

Both `/api/v1` and the generated JSON:API route follow these rules. A missing or malformed new secret gets `422` on
`/api/v1`, or `400` on the generated route. A wrong or outdated token gets `403` on both. Registration never changes the
operator-owned `approval_status`, `remote_access_requested`, or `remote_access_profile`.

Request:

```json
{
  "mac_address": "00:11:22:33:44:55",
  "product_name": "atom-001122334455",
  "registration_token": "Q7d9f2k4n8s1v3x5z0a6c9e2g4i7m1o3r5t8u0w6y9A",
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

The request can also send `ipv4_address` directly; otherwise the server takes it from `metadata.ip_address`. The
schema goes in `schema_definition`, and it must include a `product`. Schemas
are limited to 65,536 encoded bytes, eight levels of nesting, and 256 map fields; anything larger is refused before it
is saved.

Pending approval response:

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "approval_status": "pending",
    "registration_token": "Q7d9f2k4n8s1v3x5z0a6c9e2g4i7m1o3r5t8u0w6y9A"
  }
}
```

After approval, send the request again with the saved `registration_token` and a saved `replacement_token`. The values
here are examples; real requests must use securely generated random secrets.

```json
{
  "mac_address": "00:11:22:33:44:55",
  "registration_token": "Q7d9f2k4n8s1v3x5z0a6c9e2g4i7m1o3r5t8u0w6y9A",
  "replacement_token": "B8e0g3l5p9t2w4y6a1c7d0f3h5j8n2q4s6v9x1z7A0C",
  "schema_definition": {
    "product": "atom-001122334455",
    "type": "object",
    "properties": {}
  }
}
```

Approved credential response:

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "approval_status": "approved",
    "api_token": "B8e0g3l5p9t2w4y6a1c7d0f3h5j8n2q4s6v9x1z7A0C"
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

### Heartbeat

A heartbeat authenticates with the device's runtime token. It marks the device as seen (`last_seen_at`), delivers its
telemetry, and collects any commands or remote-access instructions. A device over its limit gets HTTP `429`.

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
  "ssh_host_key": "ssh-ed25519 AAAA...",
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

`ssh_host_key` is the device sshd's Ed25519 public host key. RSA and ECDSA keys are not supported: only a complete
`ssh-ed25519` key with a 32-byte key is accepted, and browser terminals only accept `ssh-ed25519` host keys. Any other
key, or a truncated, padded, or malformed one, is logged and ignored; the heartbeat still succeeds.

The first key received over an authenticated heartbeat is trusted automatically. If a different key shows up later, it
is held as pending, and browser terminals are blocked until an authorized operator trusts the new key. The device
keeps a record of the previous fingerprint, who trusted the new one, and when.

Before trusting a new key, the device page asks the operator to confirm the fingerprint some other way, for example on
the device console or from a reimaging record. Trust applies only to the exact fingerprint the operator reviewed. If
the trust state changes while someone is looking at it, their action is refused and they have to review the current
fingerprint again. A heartbeat that hits such a conflict, or fails to save a key change, simply tries again on the next
poll. Telemetry and commands carry on as normal, and the other trust decision is never overwritten.

`command_inventory` is optional, sits at the top level, and is not trusted. The client reports only the packages and
commands named in the server's latest `command_inventory_probe`. The server uses it to check compatibility; it never
grants any permission on the device.

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

The client keeps the probe and reports the matching inventory on a later heartbeat. Without a probe, it leaves out
`command_inventory`. A non-empty `connection_status.error` reports a problem with the client's FRP profile or tunnel;
it grants nothing.

Remote-access response:

```json
{
  "data": {
    "remote_access_token": "<signed-device-frp-credential>",
    "remote_access_expires_at_ms": 1900000000000,
    "remote_access_lease_id": "11111111-2222-3333-4444-555555555555",
    "remote_access_profile": {
      "name": "default",
      "version": 1
    },
    "commands": []
  }
}
```

`remote_access_expires_at_ms` is when the credential expires, in Unix milliseconds. That is the earlier of the lease's
expiry and the credential's maximum signing age. The client renews the credential shortly before it expires, rather
than restarting every time the signature changes. `remote_access_lease_id` identifies the lease currently in effect.
If it changes, the client restarts `frpc`, even when the profile is the same or the expiry is later. FRPS only accepts
a credential while its own lease is still in effect, so a revoked credential cannot ride on another lease.

When several leases are open, a provisioning lease wins over browser and direct leases; otherwise the newest one wins,
with the UUID breaking ties. A lease's profile and expiry always go together. Closing the winning lease hands over to
the next one without revoking anyone else's access. Changing a device's profile affects future leases only, not open
ones.

After a revocation, FRPS refuses new logins and proxies at once. A tunnel that is already connected stops when the
device's next authenticated heartbeat withdraws access.

`remote_access_profile` always comes with a token. It names a versioned profile defined in the client's own
configuration, and carries no `frpc` config, plugin options, or local targets. The client refuses a token that arrives
without a profile, and reports it in `connection_status.error`.

Version 1 covers today's route kinds and loopback targets. A new route kind or target has to be added to the client's
typed profile definitions, and reviewed, before it can be used, and any change to what a route means needs a new
profile version. The server only ever sends a name and a version, never route definitions, plugin options, headers, or
targets. For example, the `Host: localhost` rewrite used by the `atomixos-bootstrap` route comes from the client's own
profile, not from the heartbeat.

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

Authentication failures use the standard error format:

```json
{
  "error": {
    "code": "invalid_api_key",
    "message": "Bearer token is invalid"
  }
}
```

A device that is not approved gets its own error:

```json
{
  "error": {
    "code": "device_not_approved",
    "message": "Device is not approved"
  }
}
```

### Command Results

Results are matched to commands by `command_id`. The server acknowledges results for commands it sent to this device,
and ignores any other IDs.

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
    "message": "Bearer token is required"
  }
}
```

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
    "message": "Bearer token is invalid"
  }
}
```

### Caddy Domain Approval

Caddy asks this endpoint before issuing an on-demand certificate, passing the host as `domain`. It answers HTTP `204`
with an empty body when the host is allowed.

Allowed reserved host example:

```http
GET /api/v1/check_domain?domain=nixstasis.devices.example.com
```

Allowed device host example (the device UUID without dashes, while the device has an active lease):

```http
GET /api/v1/check_domain?domain=atom-11111111222233334444555555555555.devices.example.com
```

Denied host response:

```json
{
  "error": "The host is not permitted"
}
```

## Builder API

The alert rule and custom report builders in the web UI get their field dropdowns from the schemas devices report. The
same data is available to other tools through three generated routes, described in
`packages/server/priv/static/openapi.yaml`:

| Endpoint                                                                             | Purpose                                                        |
|--------------------------------------------------------------------------------------|----------------------------------------------------------------|
| `GET /api/json/builder_contract/schema_references`                                   | List the schemas devices report, as product and version pairs. |
| `GET /api/json/builder_contract/schemas/:schema_id/versions/:schema_version/options` | Get the dropdown options for one schema.                       |
| `POST /api/json/builder_contract/builder_configurations/validate`                    | Check a set of selections against the current schema.          |

They need a verified operator with permission to view reports. Successful responses are plain JSON payloads, and
validation answers `201`. Errors use the JSON:API format: `400` for a bad request, `403` without permission, and `404`
for a schema that does not exist.

If devices with the same `(product_name, schema_version)` report different definitions, the options route returns an
error rather than picking one at random. Treat that as blocking until the devices' schemas agree again.

Options response:

```json
{
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
```

### Validation

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

When schemas conflict, validation is blocked and no individual slot is cleared, because there is no reliable list of
options to check against:

```json
{
  "valid": false,
  "issues": [
    {
      "issue_code": "schema_conflict",
      "message": "Schema definitions conflict for this product/version.",
      "slot_id": null,
      "blocking": true
    }
  ],
  "cleared_slot_ids": []
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

## Report And Alert API Examples

Fetching report results needs a verified operator with permission to view reports. For telemetry reports, the server
limits rows to the operator's devices before applying any report filters, sorting, or paging. An operator with no
device restriction sees the whole fleet.

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

Without verified sign-in the endpoint answers `401`, without report permission `403`, and for a missing report `404`,
all with empty bodies.

Alert rules have no `/api/v1` routes. Their requests and responses are described under `/api/json/alert_rules` in
`packages/server/priv/static/openapi.yaml`.

## Authentication and Session Handling

- **Operators** reach Phoenix through Caddy and AuthCrunch; Phoenix trusts their role claims only with the
  Caddy-to-Phoenix proxy credential ([Server Web](modules/server-web.md)). Browser routes use sessions with CSRF
  protection and secure browser headers.
- **Devices** send the registration-issued runtime token as `Authorization: Bearer <device-token>` on heartbeat,
  command-result, and command-payload requests. The token never appears in a URL, and query-string credentials are
  rejected. Registration itself carries no token because it issues one.
- **Browser terminals** connect to the `terminal:*` channel with a `terminal_socket` token that Phoenix exposes only
  after the device reports `ssh_authorize` succeeded. The join carries the opaque session reference and the matching
  `command_id`, and the channel rechecks the device, command type, content type, and session binding. The command
  payloads are in [API & Runtime Contracts](reference/contracts.md#browser-terminal-ssh-authorization-contract), and the
  full chain is in [Runtime Boundaries](runtime-boundaries.md#browser-terminal-authorization).
- **E2E clients** need the E2E gate enabled and the dedicated runner credential; enabling E2E grants no access by itself.
  See [E2E API](development/e2e/api.md).

## Error Handling Patterns

- **Unexpected status:** the client reports any status it does not expect as
  `API returned non-success status: <status>`.
- **Large responses:** the client reads at most 1 MiB of a JSON response before decoding, and reports a transport
  error beyond that.
- **Empty responses:** the client accepts an empty body even when it expected one.
- **Missing token:** device requests without an `Authorization` bearer token get HTTP `401` with `missing_api_key`. An
  `api_key` query parameter on its own counts as missing.
- **Invalid token:** device requests with a bad bearer token get HTTP `401` with `invalid_api_key`.
- **Unapproved device:** heartbeats from an unapproved device get HTTP `403` with `device_not_approved`.
- **Bad command results:** a request without a results list gets HTTP `400`. This route never returns `422`.
- **Generated routes:** the JSON:API device routes return JSON:API error documents; the `/api/v1` routes are unchanged.
- **Missing payload:** a command payload that does not exist gets HTTP `404`.
- **Denied certificate host:** HTTP `401` with `{"error":"The host is not permitted"}`.
- **E2E errors:** run creation returns a typed code in an `error` object.

## Versioning Strategy

- The device API has no version negotiation; `/api/v1` keeps its envelopes and status codes stable, and new device
  behavior arrives through additive fields and heartbeat directives.
- Remote-access route profiles are versioned; a new route semantic needs a new profile version
  ([Client FRP Manager](modules/client-frp-manager.md)).
- E2E run creation requires the `X-E2E-Protocol-Version` header, and journey logs use the `e2e_log.v1` schema.
