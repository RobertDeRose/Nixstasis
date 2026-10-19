# Go Client Rewrite

The agent on each device is now a single Go program that runs as a CLI and as a service. It handles the device's
identity, registration, heartbeats, telemetry scripts, server commands, `frpc`, E2E journeys, and Linux packaging. The
original plan is in the [design record](design.md).

## What changed for users

Administrators install one `nixstasis` binary and configure it with YAML, overridden by environment variables where
needed. Its subcommands register the device, run the polling service, and install, manage, and test Stary scripts.

## How it fits in

Each concern has its own internal package: configuration, identity, transport, scripts, commands, FRP, SSH
authorization, and E2E. Typed protocol code keeps the server API separate from the CLI that drives it.

## Running it

The client retries when the network fails, puts limits on how long scripts and commands can run, and keeps the device's
identity and runtime credentials on disk. It ships with systemd units and several Linux package formats.

## Differences from the design

Starlark telemetry scripts, FRPS credentials delivered with each heartbeat, in-memory SSH authorization, and command
policies replaced the earlier plans for plugins and fixed shared secrets.

## Not included

- The client supports Linux devices only.
- The original shell client is no longer supported in any form.

## Tests

- `packages/client/cmd/nixstasis/*_test.go`: the subcommands and the service entry point.
- `packages/client/internal/config/*_test.go`: YAML configuration and environment overrides.
- `packages/client/internal/identity/*_test.go`: detecting and saving the device identity.
- `packages/client/internal/transport/*_test.go`: registration, heartbeats, and the protocol.
- `packages/client/internal/commands/*_test.go` and `packages/client/internal/commandpolicy/*_test.go`: server commands
  and command policies.
- `packages/client/internal/script/*_test.go`: Starlark telemetry scripts.
- `packages/client/internal/frp/*_test.go`: starting and stopping `frpc`.
- `packages/client/internal/sshauth/*_test.go`: in-memory SSH authorization.
- `packages/client/internal/e2e/*_test.go`: E2E journeys.
- `go test ./...` in `packages/client` (`mise run test`).
- `mise run release:check`, `mise run release:verify`, and `mise run test:packaging` in `packages/client`: release
  archives and native installers.

## Related pages

- [Client CLI](../../modules/client-cli.md) and the other Client pages in the Module Reference
- [Client Installation](../../operations/client-installation.md)
- [Client-Server Interface](../../client-server-interface.md)
- `packages/client/README.md`
