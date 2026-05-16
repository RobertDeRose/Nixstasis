# Known Gaps & Unknowns

This page records missing, ambiguous, or conflicting signals observable from repository files. It does not prescribe changes.

## Missing Specs

- No spec directory `006` is present in `specs`.
- No dedicated architecture spec exists for AuthCrunch claim mapping beyond README notes.
- No dedicated production authentication contract for Phoenix-internal APIs is present beyond Caddy/AuthCrunch deployment configuration.
- No single OpenAPI document covers both `/api/v1` controller endpoints and `/e2e` endpoints in `packages/server/priv/static/openapi.yaml`; that file is generated for Ash JSON:API.

## Ambiguities

- Root prompt states Go 1.26, while `packages/client/go.mod` declares `go 1.25.4` and package guidance references Go 1.25.x.
- `packages/server/README.md` says the `specs/005-enhance-device-list` work is pending, while implementation includes device list filtering, search, sorting, selection, and bulk approve/reject handlers.
- `specs/012-improve-devices-modal/spec.md` describes device modal behavior, while current router includes `live "/devices/:id", DeviceLive.Show, :show` and API endpoints for `/api/v1/devices/:device_id/modal`.
- README describes AuthCrunch group transforms as future follow-up work; current Caddyfile authorization policy allows roles `*`.

## Conflicting Signals Between Code and Specs

- Device API contract under `specs/004-rewrite-client-go/contracts/device-api.yaml` documents `connection_status.connected`, while Go `frp.ConnectionStatus` field names should be verified from `packages/client/internal/frp/types.go` before relying on exact JSON property names outside the generated contract.
- E2E endpoints are documented in README and implemented in controllers, but production availability depends on `NixstasisWeb.Plugs.E2EEnabled` and runtime config.
- Ash JSON:API OpenAPI output covers `/api/json` resources, while the Go client uses `/api/v1` controller endpoints.

## Areas Where Intent Is Unclear

- Whether `/api/v1/devices/:device_id/modal` remains a supported API alongside the current `/devices/:id` LiveView page.
- Whether the LiveView UI should consume AuthCrunch-injected headers for role-aware behavior; README states this is future work.
- Whether all server-issued command types are intended to be limited to `list_scripts`, `install_script`, and `remove_script`; those are the supported types visible in the client handler.
- Whether Starlark `exec_cmd` is intended for normal production telemetry scripts or only explicitly configured operator use; README states production usage is deny-by-default and requires allowlisting.
- Whether `packages/frp` is intended only for image builds or also for Debian packaging in current supported releases; root README references Debian packaging while `deploy/compose` is the supported server deployment path.

Traceable references:

- `packages/client/go.mod:1-13`
- `packages/server/README.md:86-90`
- `specs/012-improve-devices-modal/spec.md`
- `packages/server/lib/nixstasis_web/router.ex:34-36`
- `packages/server/lib/nixstasis_web/router.ex:58-65`
- `README.md:341-350`
- `deploy/compose/caddy/Caddyfile:32-38`
