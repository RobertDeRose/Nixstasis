# Starlark Script System

## References

- Beads feature root: `nixstasis-r80`
- Design record: [design.md](design.md)

## Delivered Capability

The Go client executes `.stary` telemetry extensions containing YAML front matter, Starlark code, and declared output
schemas. It supports discovery, install, remove, list, test, REPL, MQTT exchange, bounded command execution, and result
reporting.

## User-Facing Behavior

Integrators can select scripts by path or unique name, validate output locally, inspect field-level schema errors, and
use the same runtime during polling. Duplicate names require explicit paths and runaway work is cancelled by both
wall-clock and deterministic interpreter-step limits.

## Design Integration

The embedded runtime converts Starlark values into Go data, validates output before heartbeat submission, and exposes
only bounded builtins. `exec_cmd` remains deny-by-default and consumes the active command policy.

## Operational Impact

Wall-clock timeouts, a fixed Starlark computation-step ceiling, schema validation, sanitized command environments,
capability checks, and deterministic command correlation limit extension failures and host-command exposure.

## Reference and Contracts

- `packages/client/README.md`
- [Client Starlark Runtime](../../modules/client-starlark-runtime.md)
- [Client Command Handler](../../modules/client-command-handler.md)

## Test Coverage

- `packages/client/internal/script/format_test.go` and `validation_test.go`: Stary parsing, front matter, and output
  schema validation for valid and invalid scripts.
- `packages/client/internal/script/runtime_test.go` and `executor_test.go`: Starlark-to-Go value conversion, timeouts,
  and runaway-execution limits.
- `packages/client/internal/script/discovery_test.go`: script discovery and duplicate-name selectors.
- `packages/client/internal/script/builtins_mqtt_test.go`, `builtins_exec_test.go`, and the
  `builtins_read_file*_test.go` files: bounded builtins, including deny-by-default `exec_cmd`.
- `packages/client/internal/script/report_test.go`: result reporting.
- `packages/client/cmd/nixstasis/scripts_test.go`, `test_script_test.go`, `repl_test.go`, and `poll_test.go`: CLI
  install, remove, list, test, REPL, and polling workflows.

## Design Reconciliation

### Delivered as Designed

The Stary format, embedded Starlark runtime, schema validation, CLI workflows, MQTT builtin, command batches, and
timeouts were delivered.

### Intentional Changes

The runtime later gained persistent server command policies, stricter environment sanitization, and shared runtime use
within each poll.

### Deferred Work

Server-side authoring and deployment is owned by the separate server Stary script workbench feature.

### Rejected or Removed Scope

Scripts do not receive unrestricted shell execution or bypass output schemas.

## Documentation Updated

- `packages/client/README.md`
- `docs/src/modules/client-starlark-runtime.md`
- `docs/src/modules/client-command-handler.md`
