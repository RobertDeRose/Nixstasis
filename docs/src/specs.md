# Specs Reference

## Spec Inventory

- `specs/001-iot-device-monitoring`: IoT monitoring feature specification, research, data model, quickstart, and tasks.
- `specs/002-add-dashboard-home`: dashboard home feature specification, contracts, data model, manual verification, quickstart, and tasks.
- `specs/003-polish-phoenix-ui`: Phoenix UI polish specification and supporting documents.
- `specs/004-rewrite-client-go`: Go client rewrite specification, data model, contract, quickstart, research, and tasks.
- `specs/005-enhance-device-list`: device list view enhancement specification, data model, context contract, quickstart, research, and tasks.
- `specs/007-starlark-script-system`: Stary/Starlark script support specification, CLI contract, data model, quickstart, research, scripting checklist, and tasks.
- `specs/008-server-client-e2e-tests`: client/server E2E test specification and supporting documents.
- `specs/009-build-schema-dropdowns`: schema dropdown specification and supporting documents.
- `specs/010-report-view-improvements`: report view improvements specification, OpenAPI contract, data model, quickstart, research, and tasks.
- `specs/011-add-rule-modal-improvements`: add-rule modal improvements specification and supporting documents.
- `specs/012-improve-devices-modal`: devices page and device detail improvements specification and supporting documents.
- `specs/013-nixstasis-packaging-migration`: packaging and deployment migration specification, runtime contracts, release artifact contract, quickstart, research, and tasks.

Traceable references:
- `specs/*/spec.md`
- `specs/*/tasks.md`
- `specs/*/data-model.md`
- `specs/*/contracts/*`

## Core Behaviors From Specs

### Device Monitoring and Dashboard

- Specs `001`, `002`, `003`, `005`, and `012` describe device monitoring, dashboard UI, device list management, device details, and UI behavior.
- Implementation locations:
  - `packages/server/lib/nixstasis/devices.ex`
  - `packages/server/lib/nixstasis/monitoring.ex`
  - `packages/server/lib/nixstasis/dashboard.ex`
  - `packages/server/lib/nixstasis_web/live/dashboard_live/index.ex`
  - `packages/server/lib/nixstasis_web/live/device_live/index.ex`
  - `packages/server/lib/nixstasis_web/live/device_live/show.ex`

### Go Client Rewrite

- Spec `004` describes the Go client rewrite and device API contract.
- Implementation locations:
  - `packages/client/cmd/nixstasis`
  - `packages/client/internal/config`
  - `packages/client/internal/identity`
  - `packages/client/internal/transport`
  - `packages/client/internal/telemetry`
  - `packages/client/internal/frp`
  - `specs/004-rewrite-client-go/contracts/device-api.yaml`

### Stary/Starlark Script System

- Spec `007` describes script discovery, installation, removal, testing, REPL behavior, MQTT, command execution, schema validation, and execution behavior.
- Implementation locations:
  - `packages/client/internal/script`
  - `packages/client/cmd/nixstasis/script.go`
  - `packages/client/cmd/nixstasis/install_script.go`
  - `packages/client/cmd/nixstasis/list_scripts.go`
  - `packages/client/cmd/nixstasis/remove_script.go`
  - `packages/client/cmd/nixstasis/test_script.go`
  - `packages/client/cmd/nixstasis/repl.go`

### Server-Client E2E Tests

- Spec `008` and README E2E section describe client-driven E2E runs, server run/result/log storage, protocol validation, idempotency, environment locks, and static E2E Pages export.
- Implementation locations:
  - `packages/client/internal/e2e`
  - `packages/client/scripts/e2e`
  - `packages/server/lib/nixstasis/e2e.ex`
  - `packages/server/lib/nixstasis/e2e/*`
  - `packages/server/lib/nixstasis_web/controllers/e2e_*`
  - `packages/server/lib/nixstasis_web/live_dashboard/e2e_page.ex`
  - `packages/server/lib/mix/tasks/e2e.export_static.ex`

### Schema Dropdowns and Report Views

- Specs `009` and `010` describe schema-driven builder dropdowns and custom report list/detail improvements.
- Implementation locations:
  - `packages/server/lib/nixstasis/schema_options.ex`
  - `packages/server/lib/nixstasis/schema_options/normalizer.ex`
  - `packages/server/lib/nixstasis/schema_options/validator.ex`
  - `packages/server/lib/nixstasis_web/controllers/builder_schema_controller.ex`
  - `packages/server/lib/nixstasis_web/controllers/builder_config_validation_controller.ex`
  - `packages/server/lib/nixstasis/reporting.ex`
  - `packages/server/lib/nixstasis/reporting/table_filters.ex`
  - `packages/server/lib/nixstasis_web/live/reports/index_live.ex`
  - `packages/server/lib/nixstasis_web/live/reports/show_live.ex`

### Alert Rule Modal Improvements

- Spec `011` describes alert-rule modal interactions.
- Implementation locations:
  - `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
  - `packages/server/lib/nixstasis_web/live/alerts/rules_live.ex`
  - `packages/server/lib/nixstasis/monitoring.ex`
  - `packages/server/lib/nixstasis/monitoring/rule_evaluator.ex`

### Packaging and Deployment Migration

- Spec `013` describes one supported Compose deployment path, native client packaging, product identity, runtime contract, and artifact pinning.
- Implementation locations:
  - `deploy/compose`
  - `packages/server/Dockerfile`
  - `packages/caddy/Dockerfile`
  - `packages/frp/Dockerfile`
  - `packages/client/.goreleaser*` if present
  - `packages/client/build/root-dir`
  - `deploy/compose/scripts/check_runtime_contract.sh`
  - `deploy/compose/scripts/render_compose.sh`
  - `deploy/compose/scripts/validate_stack.sh`

## Contracts

- Device API:
  - `specs/004-rewrite-client-go/contracts/device-api.yaml`
  - Mapped to `packages/client/internal/transport/client.go` and Phoenix `/api/v1/devices` controllers.
- Devices context:
  - `specs/005-enhance-device-list/contracts/devices_context.md`
  - Mapped to `packages/server/lib/nixstasis/devices.ex` and device LiveViews.
- Stary CLI:
  - `specs/007-starlark-script-system/contracts/cli.md`
  - Mapped to `packages/client/cmd/nixstasis/script*` and `packages/client/internal/script`.
- Report view OpenAPI:
  - `specs/010-report-view-improvements/contracts/custom-reports-view.openapi.yaml`
  - Mapped to reporting LiveViews and `Nixstasis.Reporting`.
- Compose runtime contract:
  - `specs/013-nixstasis-packaging-migration/contracts/compose-runtime-contract.md`
  - Mapped to `deploy/compose` files and validation scripts.
- Release artifact contract:
  - `specs/013-nixstasis-packaging-migration/contracts/release-artifact-contract.md`
  - Mapped to client release assets and image workflows.

## Invariants Observable In Code and Specs

- Client device API base contract uses `/api/v1/devices/...` paths.
- Device registration returns a UUID in `data.id`.
- Heartbeat response can include `remote_access_requested` and `commands`.
- Command result status values are `OK` or `FAILED` in the Go transport contract.
- E2E run creation uses protocol-version header and rejects legacy `client_version`/`server_version` fields.
- Only one active E2E run per environment is allowed by the E2E environment lock flow.
- Supported server deployment path is `deploy/compose`.
- Public HTTP ingress in the supported deployment terminates at Caddy.

Traceable references:
- `specs/004-rewrite-client-go/contracts/device-api.yaml:7-170`
- `README.md:96-116`
- `deploy/compose/README.md:5-20`
- `packages/server/lib/nixstasis/e2e.ex:61-100`
