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

## Command Catalog Resolver Contract

The server-curated command catalog is an authoring and compatibility layer above the command policy contract. Catalog entries do not change the client runtime permission format; catalog-backed assignments still resolve to the absolute-path `apply_command_policy` payload above.

Catalog resources store:

- approved catalog commands with command name, display name, category slugs, risk notes, install guidance, and active version;
- OS-family package mappings for `debian`, `fedora`, and `nixos`, each with package manager, package name, expected executable path, and install hint;
- the latest device command inventory snapshot with schema version, probe catalog version, observation time, architecture, OS release fields, package manager, package evidence, and command path evidence.

`Nixstasis.Domain.command_inventory_probe_manifest/0` returns the current non-authoritative probe catalog version (`catalog-v1` in the first server implementation), package names, and command probes. Clients may use the manifest to bound inventory collection, but it is never authorization.

`Nixstasis.Domain.preview_catalog_command_compatibility/1` accepts selected `device_ids` and `catalog_command_ids` and returns per-device command compatibility. Status values are:

| Status                  | Meaning                                                                                                                    |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|
| `stale_inventory`       | No matching inventory exists, its probe catalog version is not current, or its observation is older than `offline_window`. |
| `unsupported_os`        | The catalog has no supported mapping for the device OS family.                                                             |
| `supported`             | The catalog has a supported OS mapping, but inventory did not include package evidence for the mapped package.             |
| `missing_package`       | The catalog mapping exists, but inventory explicitly reports the mapped package as not installed.                          |
| `conflict`              | Inventory reports the catalog command at a different executable path than the server mapping expects.                      |
| `package_installed`     | The mapped package is installed, but the command path has not been resolved by inventory evidence.                         |
| `command_path_resolved` | The mapped package is installed and the observed command path matches the server mapping.                                  |

Only `command_path_resolved` is sufficient for catalog-backed assignment without further operator action. Client-reported packages, commands, or paths that do not match a server-approved catalog entry are diagnostics only and cannot create an approved policy source.

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
- [Server Scripts](../modules/server-scripts.md): internal workbench records,
  target authorization, immutable artifacts, command orchestration, and audit
  boundaries.

## Server Script Workbench Contract

The workbench's six `script_*` persistence resources are internal Ash records, not generic
JSON:API resources. Operators use `/scripts` and `/scripts/:id` through Phoenix LiveView;
`Nixstasis.Scripts` performs domain-specific authorization and orchestration.

- `run_script` is a test-only command and does not install the supplied artifact.
- `install_script` deploys a validated `ScriptVersion.rendered_content` artifact.
- Payloads up to 4,096 bytes are inline; larger payloads use the existing authenticated
  deferred-payload endpoint and are hydrated by the Go poll loop before execution.
- Server target authorization runs before any run or pending-command side effect.
- The client remains authoritative for Stary parsing, builtins, timeouts, output validation,
  and `exec_cmd` policy enforcement.
- Audit events are Logger/PubSub events with trusted operator or authenticated device actor
  identity; no separate audit table is created.

See [Stary Script Workbench operations](../operations/script-workbench.md) for operator
workflow, recovery, and retention guidance.

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
  routes under `/api/json/builder_contract/*`. The six script-workbench
  persistence resources remain internal Ash domain resources and are excluded
  from generic JSON:API until an audited external contract is designed.
- The legacy `/api/v1/builder-*` routes remain as compatibility wrappers around
  the Ash builder actions. GET wrappers keep their `application/json` `data`
  envelopes, while validation keeps its raw `application/json` result and all
  wrappers preserve their legacy status/error shapes.
- The device runtime generated contract is delivered under
  `/api/json/device_runtime/devices`: list, public registration, heartbeat,
  command-result acknowledgement, and deferred-payload fetch are available.
  Route-level `deviceApiKey` query security applies to the heartbeat and command
  actions; registration is public at the application layer and the generated
  list uses the operator bearer boundary. The Go client remains on `/api/v1`
  until a separately reviewed migration is approved.
- Other bespoke Phoenix controller APIs under `/api/v1` and `/e2e` are documented
  by the OpenAPI files in [OpenAPI Contracts](openapi/index.md) and the
  human-readable references above; they are not covered by the Ash generated
  OpenAPI document unless a route group is explicitly migrated.
