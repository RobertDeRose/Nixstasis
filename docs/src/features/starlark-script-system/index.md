# Starlark Script System

## Delivery Summary

- Beads feature root: `nixstasis-r80`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `cbae60a04ef3b5e3e2a2bf1093d7f52028bb3aeb`
- Design record: `design.md`

## Delivered Capability

The Go client executes `.stary` telemetry extensions containing YAML front matter, Starlark code, and declared output
schemas. It supports discovery, install, remove, list, test, REPL, MQTT exchange, bounded command execution, and result
reporting.

## User-Facing Behavior

Integrators can select scripts by path or unique name, validate output locally, inspect field-level schema errors, and
use the same runtime during polling. Duplicate names require explicit paths and runaway work is cancelled.

## Design Integration

The embedded runtime converts Starlark values into Go data, validates output before heartbeat submission, and exposes
only bounded builtins. `exec_cmd` remains deny-by-default and consumes the active command policy.

## Operational Impact

Timeouts, schema validation, sanitized command environments, capability checks, and deterministic command correlation
limit extension failures and host-command exposure.

## Reference and Contracts

- `packages/client/README.md`
- [Client Starlark Runtime](../../modules/client-starlark-runtime.md)
- [Client Command Handler](../../modules/client-command-handler.md)

## Validation Evidence

Parser, schema, runtime, MQTT, command, timeout, report, CLI, and polling tests cover valid and invalid scripts,
duplicate selectors, output conversion, runaway execution, and deny-by-default commands.

## Design Reconciliation

### Delivered as Designed

The Stary format, embedded Starlark runtime, schema validation, CLI workflows, MQTT builtin, command batches, and
timeouts were delivered.

### Intentional Changes

The runtime later gained persistent server command policies, stricter environment sanitization, and shared runtime use
within each poll.

### Deferred Work

Server-side authoring and deployment is tracked separately in the active script-workbench feature.

### Rejected or Removed Scope

Scripts do not receive unrestricted shell execution or bypass output schemas.

## Documentation Updated

- `packages/client/README.md`
- `docs/src/modules/client-starlark-runtime.md`
- `docs/src/modules/client-command-handler.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-r80`. Commit `cbae60a04ef3b5e3e2a2bf1093d7f52028bb3aeb`
directly introduced the Stary runtime in `packages/client/internal/script/runtime.go`.
