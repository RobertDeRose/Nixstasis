# Server Curated Command Package Catalog

A command catalog, kept on the server, sits on top of command policies. In **Scripts → Command Policies**, operators
can pick approved catalog commands and catalog categories, preview whether each one works on each device, and send
policies. Devices still receive the same `apply_command_policy` map of command names to absolute paths.

After the server asks, each device reports a small, untrusted list of the packages and commands it has, with its
heartbeat. The server keeps the latest report for each device, works out each catalog command's path from its own
mappings, and refuses catalog assignments it cannot resolve. It never installs packages, and never treats a path a
device reports as authoritative. The original plan is in the [design record](design.md).

## What changed for users

- Catalog commands and catalog categories can be selected alongside manual entries and categories.
- The preview shows each device's status for each catalog command: `command path resolved`, `supported`,
  `package installed`, `missing package`, `unsupported os`, `stale inventory`, or `conflict`.
- A missing package comes with install guidance, but assigning a policy never installs anything.
- Confirming checks compatibility again, with current data, before anything is queued.
- Compatible devices receive exact absolute paths, in the usual policy format.
- Revoking every entry sends an empty policy, which allows nothing.

What each status means, and what to do about it, is in [Command Policies](../../operations/command-policies.md).

## How it fits in

- Inventory travels only with heartbeats; there is no separate endpoint for it.
- Inventory is stored apart from telemetry, so alert and report rules cannot use it.
- The server's catalog decides what is allowed; device reports are only evidence.
- Nothing changed on the device: `exec_cmd` still checks the absolute-path allowlist it was sent.
- Assignments reuse the existing `DevicePolicyAssignment`, `DevicePolicyAssignmentSource`, and pending-command delivery.

## Running it

Set up catalog mappings before relying on catalog-backed policies. Until a device sends a current, matching report,
catalog commands show as stale or unresolved for it, while manual absolute-path entries keep working. A malformed
inventory report is ignored, so the heartbeat still delivers commands.

## Differences from the design

- **Bad inventory is ignored.** An invalid report is logged and ignored, instead of failing the heartbeat, so command
  delivery carries on.
- **No future timestamps.** A report dated in the future is treated as if it were taken now, so it cannot dodge the
  staleness check.
- **Confirm rechecks.** Confirming runs the compatibility check again, so a stale preview can never queue a policy.

## Not included

- Nixstasis does not install or fix packages.
- Policies cover whole commands, not arguments.
- Catalog categories are flat, with no nesting or inheritance.
- The built-in catalog covers a starter set of diagnostic commands.
- Commands a device discovers are never approved automatically, catalog IDs are never sent to devices as permissions,
  and manual absolute-path entries are still supported.

## Tests

- `packages/server/test/nixstasis/command_catalog/catalog_resolver_test.exs`: catalog mappings, inventory reports, and
  compatibility statuses.
- `packages/server/test/nixstasis/command_allowlists/` (`policy_resolver_test.exs`,
  `device_policy_assignment_test.exs`, `policy_delivery_result_test.exs`): catalog-backed assignments become the
  absolute-path `apply_command_policy` payload, including revoking.
- `packages/server/test/nixstasis/monitoring/heartbeat_test.exs` and
  `packages/server/test/nixstasis_web/controllers/heartbeat_controller_test.exs`: inventory probes in heartbeats, saving
  reports, and ignoring invalid ones.
- `packages/server/test/nixstasis_web/live/command_policy_live_test.exs`: picking catalog commands, the compatibility
  preview, rechecking on confirm, and manual entries alongside.
- `packages/client/internal/inventory/inventory_test.go`: collecting a bounded package and command report.
- `packages/client/internal/transport/client_runtime_test.go`, `packages/client/internal/commands/handler_test.go`, and
  `packages/client/cmd/nixstasis/poll_test.go`: reporting inventory in heartbeats, and handling policies.
- `golangci-lint run` over the client inventory, transport, command, and CLI packages.
- `mise run docs:build`.

## Related pages

- [Command Policies](../../operations/command-policies.md)
- [API & Runtime Contracts](../../reference/contracts.md#command-catalog-resolver-contract)
- [Client-Server Interface](../../client-server-interface.md)
- [Data Flow](../../data-flow.md#command-policy-catalog-resolution)
- [Server Domain](../../modules/server-domain.md)
- [Client Transport](../../modules/client-transport.md)
- [Client Starlark Runtime](../../modules/client-starlark-runtime.md)
- [Developer Tooling](../../development/tooling.md)
