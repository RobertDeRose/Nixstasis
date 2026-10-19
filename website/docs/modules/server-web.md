# Server Web

The Phoenix web layer: routing, request pipelines, operator permissions, controllers, LiveViews, and the terminal
channel. It decides who a browser or API request comes from, and what they may do, before the request reaches the data
layer. The data layer's own access rules are in [Server Domain](server-domain.md).

## Owns

- `NixstasisWeb.Router` in `packages/server/lib/nixstasis_web/router.ex`: every pipeline, scope, and route. It is the
  definitive list of routes.
- `NixstasisWeb.Endpoint`, which mounts the LiveView socket at `/live` and the terminal socket at `/socket`.
- Operator permissions: `NixstasisWeb.OperatorContext` and the permission plugs under
  `packages/server/lib/nixstasis_web/plugs/`.
- Controllers, LiveViews, components, and channels under `packages/server/lib/nixstasis_web/`.

## Entry points

| Scope                  | Pipeline        | Serves                                                                                                           |
|------------------------|-----------------|------------------------------------------------------------------------------------------------------------------|
| `/`                    | `:browser`      | Operator LiveViews: dashboard, devices, alerts and alert rules, reports, scripts and command policies, settings. |
| `/api/v1`              | `:api`          | The device protocol used by the client, report results, and Caddy's `check_domain`.                              |
| `/api/v1/provisioning` | `:operator_api` | AtomixOS bootstrap deliveries: create, show, and withdraw. See [Server Provisioning](server-provisioning.md).    |
| `/api/json`            | `:json_api`     | The generated Ash JSON:API and Swagger UI.                                                                       |
| `/internal/frp`        | `:frp_plugin`   | FRPS plugin callbacks that authorize tunnels and HTTP access. See [Gateway FRP](gateway-frp.md).                 |
| `/e2e`                 | `:e2e_api`      | The E2E run API. See [Server E2E](../development/e2e/server.md).                                                 |
| `/_nixstasis/laptop`   | `:api`          | Recent on-demand TLS decisions for laptop diagnostics.                                                           |
| `/dev`, `/admin`       | `:browser`      | LiveDashboard, the mail preview, and AshAdmin; compiled only when development routes are enabled.                |

Request and response shapes are in the [OpenAPI Contracts](../reference/openapi/index.md); the `/api/v1` versus
`/api/json` split is described in [API & Runtime Contracts](../reference/contracts.md).

## Boundaries

- **Pipelines:** `:api` and `:operator_api` apply `NixstasisWeb.Plugs.RateLimiter`. `:json_api` adds
  `JsonApiPermissions`, which installs the operator's permissions as the Ash actor. `:e2e_api` requires
  `E2EEnabled` and authenticates the dedicated runner with `E2EAuthorization`. `:browser` applies `DevicePermissions`.
- **Operator roles:** `OperatorContext` derives permissions from the role claim headers that Caddy and AuthCrunch
  forward. Caddy maps roles to `nixstasis/viewer`, `nixstasis/operator`, and `nixstasis/admin`. In production, a missing
  or unknown role gets no access. The capabilities of each role are in the
  [Operator Role Contract](../reference/contracts.md#operator-role-contract). LiveViews recheck permission on every
  state-changing event.
- **Forwarded scope is ignored:** headers such as `X-Token-Device-Ids` are never trusted. Phoenix works out device
  scope itself.
- **Local development:** in the dev and test environments only, a request without claim headers gets default
  development permissions.
- **Terminal channel:** joining a `terminal:*` topic needs a Phoenix token signed for `terminal_socket`. The join must
  also present a short-lived session reference that the server recognizes before any SSH connection starts.
- Business rules belong to the contexts: the `/scripts` LiveViews call `Nixstasis.Scripts`, which enforces target
  authorization itself ([Server Scripts](server-scripts.md)), and the alert LiveViews call `Nixstasis.Monitoring`
  ([Server Monitoring](server-monitoring.md)).
