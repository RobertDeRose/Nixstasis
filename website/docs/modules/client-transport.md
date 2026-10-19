# Client Transport

How the client talks to Phoenix over HTTP, and the rules every connection follows: HTTPS only, a narrow loopback
exception, no redirects, and capped response sizes.

## Owns

- `packages/client/internal/transport/client.go`: the `Client` type and the request and response types for
  registration, heartbeats, command results, and deferred payloads.
- The HTTP client built by `NewHTTPClient` from the `api` configuration.

## Entry points

| Method                                                     | Route                                                                                              |
|------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| `RegisterDeviceCredentials`                                | `POST /api/v1/devices/register`                                                                    |
| `PollWithInventoryAndHostKey`, `PollWithInventory`, `Poll` | `POST /api/v1/devices/{id}/heartbeat`                                                              |
| `SendCommandResults`                                       | `POST /api/v1/devices/{id}/command_results`                                                        |
| `FetchCommandPayload`                                      | `GET /api/v1/devices/{id}/command_payloads/{ref}`; `ValidatePayloadRef` checks the reference first |

`SetAPIKey` installs the runtime token, sent as `Authorization: Bearer`. The poll loop uses
`PollWithInventoryAndHostKey`, the only variant that sends command inventory and the device's SSH host key. Request and
response shapes are in the Device API under [OpenAPI Contracts](../reference/openapi/index.md).

## Boundaries

- **HTTPS only:** requests verify certificates and hostnames. A private CA must be in the OS trust store or supplied as
  a PEM bundle through `SSL_CERT_FILE`.
- **Loopback exception:** `api.allow_loopback_http` (default `false`) allows plain HTTP to `localhost` or a loopback IP
  for local mocks only. It bypasses proxies and dials `localhost` as `127.0.0.1`; LAN and Compose HTTP URLs are still
  rejected.
- **Base URL:** userinfo, query strings, and fragments are rejected, and an invalid URL fails before any request.
- **Redirects are never followed,** so registration bodies and runtime credentials cannot leak to another URL.
- **Response bodies are limited to 1 MiB** before decoding.
- Operators set these options as described in [Client Installation](../operations/client-installation.md#point-the-client-at-the-server).
- This package depends on `internal/config`, `internal/identity`, `internal/frp`, and `internal/telemetry`.
