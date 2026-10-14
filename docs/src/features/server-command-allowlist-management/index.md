# Server Command Allowlist Management

## References

- Beads feature root: `nixstasis-01n`
- Design record: [design.md](design.md)

## Delivered Capability

Operators can author absolute-path command entries, organize them with categories, preview resolved device policies,
and deliver versioned `apply_command_policy` snapshots through the existing device command channel.

## User-Facing Behavior

The Command Policies LiveView supports entry, category, assignment, preview, conflict, retry, revoke, and delivery-status
workflows. Device-scoped permissions constrain visible devices and mutation targets.

## Design Integration

The server owns auditable policy intent; the Go client durably applies monotonic revisions and remains the deny-by-default
execution boundary for Stary `exec_cmd`. Existing command results carry acknowledgements and failures.

## Operational Impact

Offline and unsupported clients retain visible pending or failed states. Removing assignments sends a higher-revision
replacement, and an empty delivered policy denies all commands.

## Reference and Contracts

- [Command Policies](../../operations/command-policies.md)
- [Client-Server Interface](../../client-server-interface.md)
- [Data Flow](../../data-flow.md)

## Test Coverage

- `packages/server/test/nixstasis/command_allowlists/command_entry_test.exs` and `category_test.exs`: entry and
  category resources.
- `packages/server/test/nixstasis/command_allowlists/policy_resolver_test.exs`: effective-policy resolution and
  conflicts.
- `packages/server/test/nixstasis/command_allowlists/device_policy_assignment_test.exs`: scoped assignment, revision,
  and revocation.
- `packages/server/test/nixstasis/command_allowlists/policy_delivery_result_test.exs`: delivery acknowledgement and
  failure results.
- `packages/server/test/nixstasis_web/live/command_policy_live_test.exs` and
  `packages/server/test/nixstasis_web/controllers/command_policy_controller_test.exs`: Command Policies workflows and
  device-scoped authorization.
- `packages/client/internal/commandpolicy/store_test.go`: durable policy persistence, idempotency, stale revisions, and
  conflicts.
- `packages/client/internal/commands/handler_test.go`: policy ingestion and fail-closed command execution.

## Design Reconciliation

### Delivered as Designed

Command entries, categories, scoped assignments, effective-policy preview, versioned delivery, acknowledgement, and
revocation were delivered.

### Intentional Changes

Category membership is modeled through category records and entry relationships while preserving additive resolution.

### Deferred Work

Argument policies, nested categories, dynamic groups, CSV export, and automatic drift remediation remain deferred.

### Rejected or Removed Scope

The feature does not authorize shell fragments, infer permissions from scripts, or replace client enforcement.

## Documentation Updated

- `docs/src/operations/command-policies.md`
- `docs/src/client-server-interface.md`
- `docs/src/data-flow.md`
- `docs/src/modules/client-command-handler.md`
- `docs/src/modules/client-starlark-runtime.md`
