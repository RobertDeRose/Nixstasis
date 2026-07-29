# Server Curated Command Package Catalog

## Delivery Summary

- Beads feature root: `nixstasis-o4t`
- Status: delivered
- Pull request: not created by close-out
- Merge commit: fast-forward delivery records the final target in Beads
- Design record: [design.md](design.md)

## Delivered Capability

Nixstasis now provides a server-owned command/package catalog above the existing command-policy runtime. Operators can select approved catalog commands and catalog categories in **Scripts → Command Policies**, preview per-device compatibility, and queue policies that still deliver the existing `apply_command_policy` command-name to absolute-path map.

Clients report bounded, untrusted package and command evidence during heartbeat after receiving a server probe. The server persists the latest snapshot per device, resolves catalog selections against server-owned mappings, and blocks unresolved catalog assignments instead of installing packages or trusting client-reported paths as authority.

## User-Facing Behavior

- Operators can select catalog commands or catalog categories alongside existing manual command entries and categories.
- Preview shows per-device catalog states including `command_path_resolved`, `supported`, `package_installed`, `missing_package`, `unsupported_os`, `stale_inventory`, and `conflict`.
- Missing packages display install guidance, but assignment has no package-install side effects.
- Confirmation rechecks current resolver output before queueing a policy.
- Compatible devices receive exact absolute command paths in the current client policy format.
- Revoking all command policy entries queues an empty policy, preserving deny-by-default behavior.

## Design Integration

The feature preserves established boundaries:

- Heartbeat remains the only client inventory transport; no inventory-specific client endpoint was added.
- Inventory is stored outside telemetry and is not available to alert/report rule evaluation.
- Server catalog records remain policy authority; client inventory is evidence only.
- Client runtime enforcement remains unchanged: Stary `exec_cmd` checks the delivered absolute-path allowlist.
- Assignment delivery reuses existing `DevicePolicyAssignment`, `DevicePolicyAssignmentSource`, and pending-command delivery.

## Operational Impact

Operators should seed or maintain catalog mappings before relying on catalog-backed policies. Devices without current matching inventory appear as stale or unresolved for catalog assignment while manual absolute-path policies continue to work. Invalid inventory is ignored as best-effort evidence so heartbeat command delivery continues.

## Reference and Contracts

- [Command Policies](../../operations/command-policies.md)
- [Client-Server Interface](../../client-server-interface.md)
- [Data Flow](../../data-flow.md)
- [Server Domain](../../modules/server-domain.md)
- [Client Transport](../../modules/client-transport.md)
- [Client Starlark Runtime](../../modules/client-starlark-runtime.md)
- [API & Runtime Contracts](../../reference/contracts.md)
- [Developer Tooling](../../development/tooling.md)

## Validation Evidence

Focused checks passed during implementation and close-out:

- `packages/server`: `mise x -- mix test`
- `packages/server`: focused catalog, heartbeat, and command-policy LiveView tests
- `packages/client`: `mise x -- go test ./internal/commands ./internal/inventory ./internal/transport ./cmd/nixstasis`
- `packages/client`: `mise x -- golangci-lint run ./internal/commands ./internal/inventory ./internal/transport ./cmd/nixstasis`
- Repository docs: `uv run scripts/check-docs.py` and `mdbook build docs`

Known unrelated limitation: full client `go test ./...` currently fails in untouched `internal/script` slow-script warning coverage. Full repository `mise run check` also encounters pre-existing Markdown validation debt tracked outside this feature.

## Design Reconciliation

### Delivered as Designed

- Server catalog resources, package mappings, inventory snapshots, seed data, and compatibility resolver were added.
- Client heartbeat inventory probes and bounded package/command evidence reporting were added.
- Command policy authoring supports catalog commands and categories while preserving manual entries.
- Catalog-backed assignments resolve to absolute paths before delivery.
- Missing packages, unsupported OS families, stale inventory, and conflicts block catalog-backed confirmation.
- Package installation remains out of scope.

### Intentional Changes

- Invalid inventory is logged and ignored instead of failing heartbeat, preserving command delivery for malformed optional evidence.
- Future-dated client observation times are clamped to server time to preserve stale-inventory safety.
- Confirmation re-runs compatibility resolution to avoid queueing from stale UI preview state.

### Deferred Work

- Package installation/remediation workflows.
- Argument-level command policies.
- Nested catalog categories or inheritance.
- Broader catalog seed coverage beyond initial diagnostic commands.

### Rejected or Removed Scope

- Trusting client-discovered commands as approved catalog entries.
- Sending catalog IDs to the client as runtime authority.
- Installing missing packages during policy assignment.
- Replacing manual absolute-path command policies.

## Documentation Updated

- `docs/src/features/server-curated-command-package-catalog/design.md`
- `docs/src/planned-features.md`
- `docs/src/SUMMARY.md`
- `docs/src/features/index.md`
- `docs/src/operations/command-policies.md`
- `docs/src/client-server-interface.md`
- `docs/src/data-flow.md`
- `docs/src/modules/server-domain.md`
- `docs/src/modules/client-transport.md`
- `docs/src/modules/client-starlark-runtime.md`
- `docs/src/reference/contracts.md`
- `docs/src/development/tooling.md`

## Audit Trail

- `bf954e7` — reviewed design and implementation graph.
- `d564990` — server catalog resources, resolver, seed data, and tests.
- `2f56849` — command policy catalog authoring UI and compatibility preview.
- `132e320` — client inventory collection and heartbeat reporting.
- `fe2e578` — heartbeat inventory persistence/probe response and absolute-path delivery validation.
- `82a8742` — catalog policy client enforcement/revocation validation and tooling docs.

Implementation review artifacts were recorded in Beads for `nixstasis-o4t.7.1` through `nixstasis-o4t.7.5`. Close-out holistic review artifacts are recorded on `nixstasis-o4t.10` and `nixstasis-o4t.11`.
