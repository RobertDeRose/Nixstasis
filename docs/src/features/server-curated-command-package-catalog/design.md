# Design — Server Curated Command Package Catalog

## Metadata

- Beads feature root: `nixstasis-o4t`
- Feature slug: `server-curated-command-package-catalog`
- Design path: `docs/src/features/server-curated-command-package-catalog/design.md`
- Implemented record: `docs/src/features/server-curated-command-package-catalog/index.md`
- Base branch: `dev`
- Status: draft

## Feature Summary

Add a server-owned package and command catalog that lets operators author command policies from approved package-backed commands instead of manually typing absolute executable paths. Clients report bounded package and command evidence during heartbeat, but the server catalog remains the policy authority. The delivered client policy remains the existing versioned `apply_command_policy` payload containing exact command-name to absolute-path mappings.

## User Intent

Operators should be able to choose commands such as `df` from a curated catalog and understand whether selected devices support the command before assignment. Device-reported inventory is verification evidence only; a client must not be able to grant itself new `exec_cmd` permissions by advertising package names, command names, or paths.

## Goals

- Provide a server-curated catalog of approved package-backed commands, categories, descriptions, supported OS families, package mappings, command names, expected paths, risk notes, and installation guidance.
- Extend client heartbeat data with bounded OS, architecture, package-manager, package, and command-path evidence.
- Show per-device compatibility for catalog-backed policy sources before assignment.
- Resolve catalog-backed selections into the existing per-device absolute-path command policy shape.
- Preserve deny-by-default client enforcement and existing manual absolute-path policy support.

## Non-Goals

- Arbitrary package search or installation from public repositories.
- Silent package installation during policy assignment.
- Argument allowlisting, shell-fragment policies, or direct interactive command execution.
- Trusting discovered client inventory as a source of approved catalog entries.
- Replacing the existing `apply_command_policy` runtime contract.

## User-Facing Behavior

- Command policy authors can select curated commands and catalog categories in **Scripts → Command Policies**.
- Manual command entries remain available for operators who need explicit absolute-path policies outside the catalog.
- Before assignment, the UI shows each target device as `supported`, `package_installed`, `command_path_resolved`, `missing_package`, `unsupported_os`, `stale_inventory`, or `conflict`.
- Assignments proceed only for devices whose selected catalog commands resolve to unambiguous absolute paths.
- Package installation guidance is visible when a package is missing, but installation is an explicit future operator action, not an assignment side effect.

## Requirements

### Functional Requirements

- Add server catalog records for commands, packages, OS-family mappings, categories, descriptions, risk notes, and installation guidance.
- Support Debian/Ubuntu, Fedora/RHEL, and NixOS mappings explicitly; other distributions resolve to unsupported until cataloged.
- Extend heartbeat response data with a server-owned, non-authoritative `command_inventory_probe` manifest containing the catalog version, package names, and command names/expected paths the client should inspect.
- Extend heartbeat request data with a versioned `command_inventory` object containing OS release fields, architecture, package manager, observed packages, observed command paths, probe catalog version, schema version, and observation timestamp.
- Persist the latest inventory snapshot per device with observation time, schema version, and probe catalog version.
- Resolve catalog selections against server catalog mappings first and matching-probe client inventory evidence second.
- Reject or block assignment when the server catalog lacks an approved mapping, inventory is stale, a package is missing, an OS is unsupported, or reported paths conflict with catalog expectations.
- Queue the existing `apply_command_policy` command with resolved absolute paths after a catalog-backed assignment is confirmed.

### Quality Requirements

- Treat all inventory as untrusted input. Unknown client-reported commands, packages, and paths may improve diagnostics only after matching a server catalog entry.
- Keep compatibility checks deterministic and explainable in tests and UI copy.
- Avoid new client endpoints; heartbeat request and response extensions remain the inventory reporting/probe path.
- Bound inventory size by the server probe manifest and sanitize strings before persistence or display.
- Extract top-level heartbeat inventory separately from telemetry so package/path evidence is not stored as telemetry or evaluated by monitoring rules.

### Compatibility and Migration Requirements

- Existing manual command entries, categories, assignment status, and command delivery behavior must keep working.
- Clients that do not send `command_inventory` appear with `stale_inventory` or `unsupported` compatibility rather than receiving broader permissions.
- Existing clients continue to enforce delivered absolute-path policies without understanding catalog metadata.
- Clients that understand policy delivery but not inventory probes keep working for manual policies and are ineligible for catalog-backed assignment until upgraded.

## Existing Context

The completed command allowlist feature already provides manual command entries, categories, assignment preview, delivery status, and versioned client policy delivery. The Go client persists accepted server policies and uses them as the active `exec_cmd` allowlist. Client polling already sends heartbeat telemetry and receives server commands through `/api/v1/devices/:id/heartbeat`.

Relevant source and documentation:

- `docs/src/features/server-command-allowlist-management/design.md`
- `docs/src/features/server-command-allowlist-management/index.md`
- `docs/src/operations/command-policies.md`
- `docs/src/client-server-interface.md`
- `docs/src/data-flow.md`
- `docs/src/modules/client-starlark-runtime.md`
- `docs/src/modules/server-domain.md`
- `packages/client/internal/transport/client.go`
- `packages/client/internal/commands/handler.go`
- `packages/server/lib/nixstasis/command_allowlists.ex`
- `packages/server/lib/nixstasis/command_allowlists/policy_resolver.ex`
- `packages/server/lib/nixstasis_web/live/command_policy_live/index.ex`

## Proposed Design

Introduce a catalog layer above the existing command allowlist runtime contract.

1. The server returns an optional `command_inventory_probe` object in heartbeat responses. The probe is server-owned evidence guidance, not authorization. It contains `catalog_version`, package probes, and command probes for catalog entries the server is willing to verify in v1.
2. The client reports bounded inventory evidence during a later heartbeat, keyed to the probe catalog version:
   - `schema_version`
   - observation timestamp
   - probe catalog version
   - normalized architecture
   - selected `/etc/os-release` keys (`ID`, `ID_LIKE`, `VERSION_ID`, `PRETTY_NAME`)
   - detected package manager (`apt`, `dnf`, `rpm`, `nix`, `unknown`)
   - package evidence only for package names included in the latest probe manifest
   - command path evidence only for command names included in the latest probe manifest
3. The heartbeat controller extracts top-level `command_inventory` separately from `telemetry`, sanitizes/bounds it, and persists the latest inventory snapshot on or beside the device record. Inventory is not telemetry and is not available to alert/report rule evaluation.
4. Server-owned catalog records define approved catalog command keys, display names, categories, packages, OS-family mappings, expected command paths, and operator guidance.
5. Compatibility resolution combines catalog mappings with matching-probe inventory evidence. The catalog must approve a command before any inventory observation is considered. A catalog entry outside the active probe manifest is `stale_inventory` until the device reports evidence for that probe version.
6. Policy assignment reuses and extends `DevicePolicyAssignmentSource` with catalog source kinds such as `catalog_command` and `catalog_category`; `source_snapshot` records the catalog version and resolved provenance. It must not introduce a parallel assignment-source model unless implementation evidence proves reuse impossible.
7. Catalog-backed assignments resolve per device and emit the existing absolute-path `apply_command_policy` payload.
8. The client enforces the same `RuntimeConfig.ExecCommandAllowlist` map it already enforces; catalog metadata never reaches the runtime as authority.

## Architecture Consistency

### Existing Patterns Reused

- Existing heartbeat request/response path for client-server runtime data.
- Existing command policy LiveView and preview workflow.
- Existing `apply_command_policy` command result and payload-ref delivery path.
- Existing Stary `exec_cmd` deny-by-default enforcement.
- Ash resources and `Nixstasis.Domain` APIs for server-owned policy data.

### Invariants Preserved

- The client runtime remains the final enforcement boundary.
- Server policy authority is operator-authored and auditable.
- Device API tokens authenticate device runtime traffic only; browser/operator authorization remains separate.
- Clients cannot expand permissions through self-reported inventory.
- Empty delivered policies still mean deny all.

### New Decisions Introduced

- Heartbeat request/response extensions are the v1 inventory probe and reporting channel; no inventory-specific `/api/v1` endpoint is added.
- Inventory freshness reuses the existing server `offline_window` setting, currently defaulting to 10 minutes. Resolver status is `stale_inventory` when the latest inventory is missing, has no matching probe catalog version, or was observed before the current offline window.
- Catalog assignments resolve to absolute paths before delivery; clients do not receive catalog IDs as permission authority.
- Catalog assignment sources extend the existing device policy assignment source model instead of creating a second assignment framework.
- Package installation is deferred and must be modeled as a separate explicit, audited operator action if added later.

### Architecture Documentation Changes

- Update data-flow and client/server interface docs with `command_inventory` heartbeat evidence.
- Update server-domain docs with catalog resources and resolver statuses.
- Update command-policy operations docs with catalog-backed authoring behavior.

## Operational Considerations

- Compatibility status can be stale when a device has not heartbeated recently or has not reported the active probe catalog version; stale inventory blocks catalog assignment for that device.
- Unsupported OS families and missing packages produce guidance rather than automatic remediation.
- Catalog maintenance becomes an operator/server responsibility. New entries should be tested against supported distributions before use.
- Existing retry, revoke, and delivery-status workflows continue after catalog-backed policies are converted to absolute-path payloads.

## Documentation Impact

| Documentation concern      | Exact page                                                          | Create or update        | Planned change                                                                                                   | Owning Beads task   |
|----------------------------|---------------------------------------------------------------------|-------------------------|------------------------------------------------------------------------------------------------------------------|---------------------|
| Architecture               | `docs/src/data-flow.md`                                             | Update                  | Document heartbeat inventory and catalog-backed policy resolution flow.                                          | `nixstasis-o4t.7.4` |
| Architecture               | `docs/src/modules/server-domain.md`                                 | Update                  | Add catalog resources, inventory snapshots, and resolver statuses.                                               | `nixstasis-o4t.7.2` |
| Architecture               | `docs/src/modules/client-starlark-runtime.md`                       | Update                  | Clarify unchanged absolute-path enforcement after catalog resolution.                                            | `nixstasis-o4t.7.4` |
| Usage / Operations         | `docs/src/operations/command-policies.md`                           | Update                  | Explain catalog command selection, compatibility warnings, missing-package guidance, and manual-entry fallback.  | `nixstasis-o4t.7.3` |
| Reference                  | `docs/src/client-server-interface.md`                               | Update                  | Define `command_inventory_probe` and `command_inventory` heartbeat shapes and inventory error/fallback behavior. | `nixstasis-o4t.7.1` |
| Reference                  | `docs/src/modules/client-transport.md`                              | Update                  | Document Go transport request/response fields for inventory probes and inventory evidence.                       | `nixstasis-o4t.7.1` |
| Reference                  | `docs/src/reference/contracts.md`                                   | Update                  | Define catalog-backed command policy resolver and compatibility statuses.                                        | `nixstasis-o4t.7.2` |
| Development                | `docs/src/development/tooling.md`                                   | Update                  | Record focused validation commands for client inventory, server catalog, UI, and E2E coverage.                   | `nixstasis-o4t.7.5` |
| Navigation                 | `docs/src/SUMMARY.md`                                               | Update                  | Register this feature design.                                                                                    | `nixstasis-o4t.1`   |
| Implemented Feature Record | `docs/src/features/server-curated-command-package-catalog/index.md` | Create during close-out | Preserve delivery and audit history.                                                                             | `nixstasis-o4t.8`   |

## Validation Strategy

- Client Go tests for OS-release parsing, architecture normalization, package-manager detection, probe-manifest handling, command probing, heartbeat JSON shape, malformed inputs, package evidence, observation timestamp, schema/probe versions, and bounded inventory size.
- Server tests for catalog resources, OS-family mappings, inventory snapshot persistence with observation time/schema/probe versions, compatibility statuses, stale inventory using `offline_window`, conflicts, and unknown client-reported commands.
- LiveView tests for catalog search, category selection, compatibility preview, permission scoping, and manual-entry fallback.
- Command policy tests proving catalog selections queue the existing absolute-path `apply_command_policy` payload.
- End-to-end test that assigns a catalog-backed `df` command, observes allowed `exec_cmd`, revokes it, and observes denial.
- Documentation validation with `uv run scripts/check-docs.py` and `mdbook build docs`.
- Ash validation with `mix ash.codegen --check` when Ash resources change.

## Implementation Decomposition

- `nixstasis-o4t.7.1`: client inventory collection and heartbeat reporting.
- `nixstasis-o4t.7.2`: server catalog resources, inventory storage, and compatibility resolver.
- `nixstasis-o4t.7.3`: Command Policies LiveView catalog selection and compatibility preview.
- `nixstasis-o4t.7.4`: catalog-backed assignment delivery through existing absolute-path policy payloads.
- `nixstasis-o4t.7.5`: integration/E2E validation and development documentation.

## Dependencies and Parallelism

- All implementation children depend on `nixstasis-o4t.6` specification reconciliation.
- Client inventory and server catalog can proceed in parallel.
- Policy UI depends on server catalog resolver APIs.
- Policy delivery depends on client inventory and server catalog.
- End-to-end validation depends on UI and delivery integration.

## Rollout and Migration

- Existing manual command policies remain valid and need no migration.
- Catalog-backed policy sources are additive to the policy authoring model.
- Devices without current inventory for the active probe catalog version are not eligible for catalog-backed assignment until a heartbeat reports matching inventory.
- Catalog seed data should start with a small set of common diagnostic commands such as `df`, `uname`, and `journalctl` where mappings are known.

## Risks and Tradeoffs

- Catalog maintenance can drift across distributions; explicit OS mappings and tests reduce hidden assumptions.
- Inventory can become stale or malicious; blocking unresolved devices is safer than optimistic assignment.
- Per-device resolution adds server complexity but keeps client runtime enforcement unchanged and auditable.
- Reporting package inventory may be expensive on some systems; the client must keep probes bounded and best-effort.

## Rejected Alternatives

- Trusting discovered client command paths as policy entries: rejected because compromised clients could grant themselves permissions.
- Sending catalog IDs to clients as runtime authority: rejected because it would create a second enforcement model.
- Installing missing packages during assignment: rejected for v1 because installation crosses a stronger trust and rollback boundary.
- Replacing manual command entries: rejected because operators still need exact-path escape hatches for unsupported environments.

## Open Questions

None blocking implementation.

## Deferred Decisions

- Package installation workflow: deferred until there is explicit operator demand and a separate audited install/revert design.
- Argument-level policy: deferred until the Stary runtime has a concrete argument-policy contract.
- Nested catalog categories or inheritance: deferred; v1 categories are direct catalog groupings only.

## Planning Record

### Questions Asked and Answers

- No user question was required during roadmap-only promotion; the legacy roadmap entry and completed command-policy design supplied the implementation contract.

### Assumptions

- The implementation repository is this `nixstasis` repository because all referenced client, server, and documentation paths are local.
- The implementation base branch is `dev`; the imported `main` metadata was corrected because this repository has no `main` branch.
- Heartbeat inventory is acceptable because it reuses existing authenticated device runtime traffic and does not authorize policy by itself.

### Design Changes During Planning

- Chose heartbeat as the sole v1 inventory reporting channel.
- Made package installation explicitly deferred and non-side-effecting.
- Required catalog-backed delivery to preserve the existing absolute-path `apply_command_policy` contract.

### Source Material

- `docs/src/planned-features.md`
- `docs/src/features/server-command-allowlist-management/design.md`
- `docs/src/features/server-command-allowlist-management/index.md`
- `docs/src/features/starlark-script-system/index.md`
- `docs/src/operations/command-policies.md`
- `docs/src/client-server-interface.md`
- `docs/src/data-flow.md`
- `docs/src/modules/client-starlark-runtime.md`
- `docs/src/modules/server-domain.md`
- `docs/src/modules/server-web.md`
