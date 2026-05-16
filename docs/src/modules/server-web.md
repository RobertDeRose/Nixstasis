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
- `packages/server/lib/nixstasis_web/channels/user_socket.ex`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex`
- `packages/server/lib/nixstasis_web/components/*.ex`
- `packages/server/lib/nixstasis_web/live_dashboard/*.ex`

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

### JSON API Routes

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
- Browser UI uses Phoenix LiveView over HTTP and LiveView WebSocket transport.
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
