# Server Domain

The Ash domain: the server's stored data, the actions and access rules on it, and the JSON:API generated from it. The
permission checks that happen earlier, at the HTTP layer, are in [Server Web](server-web.md).

## Owns

- `Nixstasis.Domain` in `packages/server/lib/nixstasis/domain.ex`: the resource registry, the code interface functions
  other modules call, and the `json_api` route declarations.
- The Ash resources, grouped by context:

| Context              | Resources                                                                                                                                                   |
|----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Devices              | `Device`, `DeviceGroup`, `DeviceGroupMembership`, `PendingCommand`, `RemoteAccessLease`                                                                     |
| Command allowlists   | `CommandEntry`, `CommandEntryVersion`, `Category`, `CommandEntryCategory`, `DevicePolicyAssignment`, `DevicePolicyAssignmentSource`, `PolicyDeliveryResult` |
| Command catalog      | `Category`, `CatalogCommand`, `PackageMapping`, `DeviceInventorySnapshot`                                                                                   |
| Scripts              | `ScriptDraft`, `ScriptVersion`, `ScriptValidationRun`, `ScriptTestRun`, `ScriptDeploymentRun`, `ScriptClientAction`                                         |
| Provisioning         | `Delivery`                                                                                                                                                  |
| Monitoring           | `Alert`, `AlertRule`, `Telemetry`                                                                                                                           |
| Reporting            | `CustomReport`                                                                                                                                              |
| Settings and schemas | `SystemSetting`, `SchemaOptions.BuilderContract`                                                                                                            |

## Entry points

- **Code interface:** context modules and LiveViews call `Nixstasis.Domain` functions defined with `define` in
  `domain.ex`; that file has the full list.
- **JSON:API:** the `json_api` block exposes routes under `/api/json` for `/devices`, `/device_runtime/devices`,
  `/pending_commands`, `/alerts`, `/alert_rules`, `/telemetry_events`, `/custom_reports`, `/system_settings`, and
  `/builder_contract`. `NixstasisWeb.AshJsonApiRouter` serves them, and Swagger UI is at `/api/json/swaggerui`. The
  generated operations are committed in `packages/server/priv/static/openapi.yaml`; see
  [OpenAPI Contracts](../reference/openapi/index.md).

## Boundaries

- **Device scope:** reads of devices, pending commands, telemetry, and alerts only return rows for devices in the
  operator's scope. The scope comes from Phoenix permissions, never from forwarded claims. An operator with no scope
  restriction who can view devices sees the whole fleet. An empty scope returns nothing, and so does a scope containing
  a malformed device ID.
- **Alert rules:** reads and mutations require the actor's alert view or manage capability.
- **Device runtime actions:** heartbeat, result acknowledgement, and payload actions require the authenticated device
  actor to match the requested device ID.
- **Internal calls:** contexts and background workers call the domain without an operator, so their reads are not
  limited by device scope.
- **Validation:** command allowlist entries accept only lowercase command names and absolute paths without whitespace
  or shell metacharacters, enforced in the resource and the database. `SystemSetting` normalizes monitoring minutes and
  validates webhook destinations on every write path.
- Policy filtering depends on the `simple_sat` solver.
