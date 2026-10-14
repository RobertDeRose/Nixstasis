# Go Client Rewrite

## References

- Beads feature root: `nixstasis-9oi`
- Design record: [design.md](design.md)

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

## Test Coverage

- `packages/client/cmd/nixstasis/*_test.go`: CLI subcommands and service entry point.
- `packages/client/internal/config/*_test.go`: YAML configuration and environment overrides.
- `packages/client/internal/identity/*_test.go`: device identity detection and persistence.
- `packages/client/internal/transport/*_test.go`: registration, heartbeat, and protocol transport.
- `packages/client/internal/commands/*_test.go` and `packages/client/internal/commandpolicy/*_test.go`: server
  command handling and command policies.
- `packages/client/internal/script/*_test.go`: Starlark telemetry scripts.
- `packages/client/internal/frp/*_test.go`: FRPC lifecycle management.
- `packages/client/internal/sshauth/*_test.go`: dynamic SSH authorization.
- `packages/client/internal/e2e/*_test.go`: E2E journey support.
- `go test ./...` in `packages/client` (`mise run test`).
- `mise run release:check`, `mise run release:verify`, and `mise run test:packaging` in `packages/client`: release
  archives and native installers.

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
