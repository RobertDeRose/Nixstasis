# Server Web

## Language

- Elixir.

## Runtime Context

- Server HTTP/UI boundary.
- Phoenix Router, controllers, LiveView, channels, components, and LiveDashboard extensions.

## Purpose

- Exposes browser UI routes, JSON API routes, Ash JSON:API forwarding, E2E API routes, LiveDashboard pages, and terminal WebSocket channels.

## Key Files

- `packages/server/lib/nixstasis_web/router.ex`
- `packages/server/lib/nixstasis_web/endpoint.ex`
- `packages/server/lib/nixstasis_web/controllers/*.ex`
- `packages/server/lib/nixstasis_web/live/**/*.ex`
- `packages/server/lib/nixstasis_web/live/command_policy_live/index.ex`
- `packages/server/lib/nixstasis_web/live/command_policy_live/form_component.ex`
- `packages/server/lib/nixstasis_web/channels/user_socket.ex`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex`
- `packages/server/lib/nixstasis_web/components/*.ex`
- `packages/server/lib/nixstasis_web/live_dashboard/*.ex`
- `packages/server/lib/nixstasis_web/operator_context.ex`
- `packages/server/lib/nixstasis_web/plugs/device_permissions.ex`

## Public Interfaces

### Browser Routes

- `/`
- `/devices`
- `/devices/new`
- `/devices/:id`
- `/alerts`
- `/alerts/new`
- `/alerts/:id/edit`
- `/alerts/rules`
- `/reports`
- `/reports/new`
- `/reports/:id/edit`
- `/reports/:id`
- `/settings`
- `/scripts`
- `/scripts/command-policies`
- `/scripts/command-policies/new`
- `/scripts/command-policies/:id/edit`
- `/scripts/:id`
- `POST /scripts/command-policies/preview`

Alert rule creation and editing use the `/alerts/new` and `/alerts/:id/edit`
LiveView modal flow. The modal exposes explicit accessible title and
description targets, announces validation errors, keeps keyboard focus within
the active modal (including discard confirmation), and ignores duplicate save
events while a save is being processed. The legacy `/alerts/rules` route remains
a separate UI surface.

### JSON API Routes

Generated Ash JSON:API routes:

- `GET /api/json/builder_contract/schema_references`
- `GET /api/json/builder_contract/schemas/:schema_id/versions/:schema_version/options`
- `POST /api/json/builder_contract/builder_configurations/validate`

These builder routes are Ash generic-action RPC endpoints exposed through the
Ash JSON:API router. Successful responses are raw action payloads rather than
resource `data` documents; the generated POST action uses Ash JSON:API's `201`
success status. Generated `/api/json` routes use the `JsonApiPermissions`
pipeline and bearer/report-view authorization, with explicit `400`, `403`, and
`404` responses where applicable. The `/api/v1` wrappers use the compatibility
`:api` pipeline and rate limiter instead; use them when the legacy `200`/`422`
status and body shapes are required.

Generated device-runtime action routes:

- `GET /api/json/device_runtime/devices` — operator/device-view filtered list.
- `POST /api/json/device_runtime/devices/register` — public registration.
- `POST /api/json/device_runtime/devices/:device_id/heartbeat` — device-key heartbeat.
- `POST /api/json/device_runtime/devices/:device_id/command_results` — device-key result acknowledgement.
- `GET /api/json/device_runtime/devices/:device_id/command_payloads/:ref` — device-key deferred-payload fetch.

Heartbeat, command-result, and payload actions use the `deviceApiKey` query
scheme; registration is public at the application layer and list uses the
operator bearer/device-view boundary. The Go client remains on the compatible
`/api/v1` wrappers.

Other generated resource routes:

- `/api/json/devices`
- `/api/json/pending_commands`
- `/api/json/alerts`
- `/api/json/alert_rules`
- `/api/json/telemetry_events`
- `/api/json/custom_reports`
- `/api/json/system_settings`

The six `script_*` persistence resources remain Ash-owned for the Stary
workbench, but they are intentionally not generic JSON:API routes. The current
LiveView calls `Nixstasis.Domain` directly; exposing generic CRUD would bypass
workbench validation, command dispatch, and audit boundaries. They are therefore
excluded from the generated OpenAPI artifact until an audited external contract
is designed.

## Stary Script Workbench boundary

The `/scripts` LiveViews call `Nixstasis.Scripts` for domain-specific authoring, bounded
validation, target authorization, test/deployment queueing, retry, cancellation, and audit
emission. The context checks the trusted browser device scope before creating a run or
pending command; filtering the device list in the LiveView is not the security boundary.

`ScriptVersion.rendered_content` is the immutable artifact used by validation, `run_script`
test commands, and `install_script` deployment commands. Device results enter through the
authenticated device command controller and remain separate from operator audit identity.
See [Server Scripts](server-scripts.md) and [Stary Script Workbench](../operations/script-workbench.md).

Legacy `/api/v1` compatibility routes and bespoke controller routes:

- `GET /api/v1/builder-schemas`
- `GET /api/v1/builder-schemas/:schema_id/versions/:schema_version/options`
- `POST /api/v1/builder-configurations/validate`
- `GET /api/v1/devices`
- `POST /api/v1/devices/register`
- `POST /api/v1/devices/:device_id/heartbeat`
- `POST /api/v1/devices/:device_id/command_results`
- `GET /api/v1/devices/:device_id/command_payloads/:ref`
- `GET /api/v1/reports/:id/results`
- `GET /api/v1/check_domain`

The `/api/v1/builder-*` routes are compatibility wrappers around Ash-backed
builder actions. The generated contracts for those actions are published under
`/api/json/builder_contract/*`; GET wrappers keep their existing
`application/json` `data` envelopes, while validation returns its raw JSON result
and all wrappers preserve their legacy status/error behavior.

The device runtime retains controller-backed `/api/v1` compatibility wrappers,
while all five additive generated Ash actions are available under
`/api/json/device_runtime/devices`. The Go client remains on the compatibility
surface pending a separately reviewed client migration; report result preview
remains a deferred external-contract decision; and `GET /api/v1/check_domain`
remains a Caddy-only ingress workflow boundary.

### E2E Routes

- `GET /e2e/suites`
- `GET /e2e/runs`
- `POST /e2e/runs`
- `GET /e2e/runs/:id`
- `POST /e2e/runs/:id/cancel`
- `GET /e2e/runs/:id/results`
- `POST /e2e/runs/:id/results`
- `GET /e2e/runs/:id/results/:journey_id/log`

### Channels

- Socket channel topic pattern: `terminal:*`.
- Socket connect requires a Phoenix token signed for `terminal_socket`.
- Terminal channel join uses an opaque, expiring server-side session ref.

## Dependencies

### Internal

- `Nixstasis.Devices`
- `Nixstasis.Monitoring`
- `Nixstasis.Reporting`
- `Nixstasis.E2E`
- `Nixstasis.Deployment`
- `NixstasisWeb.Plugs.E2EEnabled`

### External

- Phoenix
- Phoenix LiveView
- Phoenix Channels
- Phoenix LiveDashboard
- OpenApiSpex
- Plug/Swoosh development routes

## Client-Server Interaction Details

- Go client device traffic uses JSON routes under `/api/v1/devices`.
- Builder automation should prefer the generated `/api/json/builder_contract/*`
  routes when JSON:API media types are acceptable; browser/UI compatibility can
  continue using `/api/v1/builder-*` wrappers.
- Browser UI uses Phoenix LiveView over HTTP and LiveView WebSocket transport.
- Browser UI permissions are derived by `NixstasisWeb.OperatorContext` from
  trusted Caddy/AuthCrunch role claim headers when present. Supported production
  role values are normalized by Caddy to `nixstasis/viewer`,
  `nixstasis/operator`, and `nixstasis/admin`; missing or unknown production
  roles fail closed for device, report, command-policy, and JSON:API
  permissions. Command-policy permissions intentionally split viewer status
  access from operator/admin access to full command paths and mutation. Requests
  without `X-Token-*` claim headers keep local-development defaults only in dev
  and test; they are not production authorization.
- The generated `/api/json` resource surface is an operator/developer API, not
  the device runtime protocol. Viewer roles may read resource data, operator
  roles may manage device/report/alert resources according to capability maps,
  and admin is required for system settings. Scoped device claims such as
  `X-Token-Device-Ids` restrict JSON:API device mutations to those IDs.
- Device detail uses the `/devices/:id` LiveView route and may render as a modal
  overlay over the Devices list; the old REST modal API is not part of the
  supported surface.
- Terminal UI uses Phoenix Channels over WebSocket.
- Caddy on-demand TLS calls `/api/v1/check_domain`.
- E2E harness calls `/e2e` routes with `X-E2E-Protocol-Version` on run creation.

Traceable references:

- `packages/server/lib/nixstasis_web/router.ex:1-117`
- `packages/server/lib/nixstasis_web/channels/user_socket.ex:37-64`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex:20-113`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex:7-62`
