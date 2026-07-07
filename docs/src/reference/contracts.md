# API & Runtime Contracts

This reference collects the durable contract-style documentation that replaced
the retired spec-kit contract files.

## HTTP APIs

- [Architecture Overview](../architecture.md): high-level API and authentication
  surfaces for browser, device, Caddy, Ash JSON:API, and E2E consumers.
- [Client-Server Interface](../client-server-interface.md): Go client `/api/v1`,
  E2E `/e2e`, authentication, response shapes, and error handling.
- [OpenAPI Contracts](openapi/index.md): generated Ash JSON:API documentation
  and maintained OpenAPI definitions for bespoke Phoenix controller APIs.
- [Server Web](../modules/server-web.md): browser routes, JSON routes, E2E
  routes, and terminal channel surface.
- [Server E2E](../modules/server-e2e.md): E2E run/result behavior and protocol
  expectations.

## Command Policy Contract

`apply_command_policy` is delivered in heartbeat `commands` using payload content type `application/vnd.nixstasis.command-policy+json;version=1`.

Payload shape:

```json
{
  "assignment_id": "uuid",
  "version": "policy-123",
  "revision": 123,
  "commands": {
    "name": "/absolute/path"
  }
}
```

Clients durably persist accepted server policies outside the scripts directory. A persisted server policy overrides local `runtime.exec_commands`; when no persisted server policy exists, local config is the fallback. An empty `commands` object is valid and means deny all.

## Client Contracts

- [Client Transport](../modules/client-transport.md): typed Go client HTTP
  boundary for registration, heartbeat, command results, and command payloads.
- [Client Command Handler](../modules/client-command-handler.md): server-issued
  command execution boundary.
- [Client Starlark Runtime](../modules/client-starlark-runtime.md): `.stary`
  script parsing, validation, execution, and telemetry output behavior.
- [Client FRP Manager](../modules/client-frp-manager.md): FRPC lifecycle and
  remote-access token handling.

## Server Contracts

- [Server Devices](../modules/server-devices.md): registration, approval,
  listing, remote access flags, pending commands, and terminal support.
- [Server Monitoring](../modules/server-monitoring.md): heartbeat, telemetry,
  alerts, and offline checks.
- [Server Reporting](../modules/server-reporting.md): custom report and query
  builder behavior.

## Runtime And Deployment

- [Deployment Compose](../modules/deployment-compose.md): Compose services,
  required operator inputs, hostname contract, Caddy ask endpoint, and artifact
  rules.
- [Edge Caddy](../modules/edge-caddy.md): AuthCrunch edge authorization and
  forwarded `X-Token-*` claim headers used by Phoenix browser permission mapping.
- [Runtime Boundaries](../runtime-boundaries.md): process, network, data, secret,
  and test-only boundaries.

## Browser Authorization Contract

- Caddy/AuthCrunch is the production browser authentication and authorization
  edge. Protected production hosts keep `authorize with entra_policy`.
- Phoenix consumes trusted forwarded headers only after Caddy admits the browser
  request: `X-Token-Subject`, `X-Token-User-Email`, `X-Token-User-Name`, and
  `X-Token-User-Roles`.
- Caddy/AuthCrunch maps provider-specific OIDC groups from
  `NIXSTASIS_VIEWER_GROUPS`, `NIXSTASIS_OPERATOR_GROUPS`, and
  `NIXSTASIS_ADMIN_GROUPS` into provider-generic roles before Phoenix sees the
  request.
- `nixstasis/viewer` grants read-only device and report access.
  `nixstasis/operator` grants remote device access and report management.
  `nixstasis/admin` currently grants the same implemented permissions as
  `operator` and is reserved for privileged settings surfaces.
- Missing, malformed, or unknown production role claims fail closed. Direct local
  Phoenix requests without `X-Token-*` claim headers keep development-only
  permissive defaults only in dev and test.
- The generated `/api/json` resource surface is protected as an
  operator/developer API. It is separate from the Go client `/api/v1/devices`
  runtime protocol and must not use device API tokens as operator credentials.
- Optional scoped device claims (`X-Token-Device-Id`, `X-Token-Device-Ids`, or
  `X-Token-Allowed-Device-Ids`) limit JSON:API device mutations to the listed
  IDs. Unscoped device creation and collection-level command/telemetry writes
  require unscoped device manage permission.

## Generated OpenAPI

- `packages/server/priv/static/openapi.yaml` documents the generated Ash
  JSON:API surface under `/api/json`, including the builder contract action
  routes under `/api/json/builder_contract/*`.
- The legacy `/api/v1/builder-*` routes remain as compatibility wrappers around
  the Ash builder actions and keep their `application/json` response envelopes.
- Other bespoke Phoenix controller APIs under `/api/v1` and `/e2e` are documented
  by the OpenAPI files in [OpenAPI Contracts](openapi/index.md) and the
  human-readable references above; they are not covered by the Ash generated
  OpenAPI document.
