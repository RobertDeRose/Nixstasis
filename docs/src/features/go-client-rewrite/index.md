# Go Client Rewrite

## Delivery Summary

- Beads feature root: `nixstasis-9oi`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `4ec70eaaf955c29538be7d8d832d53907486c99b`
- Design record: `design.md`

## Delivered Capability

The supported managed-device runtime is a Go CLI and service covering identity, registration, heartbeat polling,
telemetry scripts, server commands, FRPC lifecycle, E2E journeys, and Linux release packaging.

## User-Facing Behavior

Administrators install one `nixstasis` binary, configure it through YAML and environment overrides, register devices,
run polling services, and manage or test Stary scripts through dedicated subcommands.

## Design Integration

Focused internal packages own configuration, identity, transport, scripts, commands, FRP, SSH authorization, and E2E
behavior. Typed protocol code separates server contracts from CLI orchestration.

## Operational Impact

The client retries network failures, bounds script and command execution, persists device identity and approved runtime
credentials, and ships with systemd and multi-format Linux packaging.

## Reference and Contracts

- `packages/client/README.md`
- [Client CLI](../../modules/client-cli.md)
- [Client-Server Interface](../../client-server-interface.md)

## Validation Evidence

The Go test suite covers CLI, identity, transport, command, script, FRP, SSH authorization, and E2E packages. Release
verification covers archives and native installers. `packages/client/cmd/nixstasis/main.go` corroborates the CLI runtime.

## Design Reconciliation

### Delivered as Designed

The shell client was replaced by the single Go runtime and its focused package boundaries.

### Intentional Changes

Starlark telemetry, heartbeat-provided FRPS tokens, dynamic SSH authorization, and command policies superseded earlier
plugin and static-secret assumptions.

### Deferred Work

Platform support remains focused on Linux managed devices.

### Rejected or Removed Scope

No compatibility path retains the original shell client as a supported runtime.

## Documentation Updated

- `packages/client/README.md`
- `docs/src/modules/client-*.md`
- `docs/src/client-server-interface.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-9oi`. Commit `4ec70eaaf955c29538be7d8d832d53907486c99b`
directly migrated the packaged CLI entry point and release shape.
