# Server Command Allowlist Management

## Delivery Summary

- Beads feature root: `nixstasis-01n`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `fb4d42bc12b9dfa8e33ee2f89b1893179203512a`
- Design record: `design.md`

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

## Validation Evidence

Server resource, resolver, authorization, LiveView, and delivery-result tests cover policy lifecycle and scoping. Client
handler and policy-store tests cover persistence, idempotency, stale revisions, conflicts, and fail-closed execution.

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

## Audit Trail

Legacy tasks were imported beneath `nixstasis-01n`. Commit `fb4d42bc12b9dfa8e33ee2f89b1893179203512a`
directly tightened device-scoped assignment behavior in the central command allowlist context.
