<!-- workflow-migration:legacy-markdown-to-beads -->

# Go Client Rewrite

## Feature Name

`go-client-rewrite`

## Goal

Replace the original shell-based client with a maintainable Go CLI and service
that handles device identity, registration, polling, telemetry collection,
server command handling, and FRP lifecycle management.

## Users

- Device administrators installing and configuring managed devices.
- Operators relying on client telemetry and remote access behavior.
- Developers maintaining client/server protocol compatibility.

## Requirements

- Provide one `nixstasis` binary with subcommands for registration, polling, scripts, and support workflows.
- Load primary configuration from a config file with environment overrides.
- Detect device identity from network interfaces and persist assigned device ID.
- Register with the server and persist API credentials.
- Poll the server for heartbeat responses, commands, and remote-access tokens.
- Collect telemetry from the supported extension mechanism and merge it into heartbeat payloads.
- Manage FRPC process lifecycle for requested remote access.
- Enforce process timeouts and avoid blocking the main poll loop on slow extensions or commands.
- Produce supported release artifacts for Linux hosts.

## Proposed Design

The Go client is organized into focused internal packages: configuration,
identity, transport, telemetry/script execution, command handling, FRP
management, and E2E support. The CLI entrypoints orchestrate these packages while
keeping protocol details inside typed transport code.

The original plugin assumptions were superseded by the Starlark script system and
server-provided FRPS token flow. Durable client behavior is documented in
`packages/client/README.md`, `docs/src/modules/client-*`, and
`docs/src/client-server-interface.md`.

## Edge Cases

- Missing or corrupt local identity should trigger safe re-registration.
- Network failures should log and retry without crashing normal service operation.
- Hanging telemetry scripts or commands must time out.
- Duplicate command IDs in one batch must produce deterministic command results.
- FRPC token rotation must restart active FRPC safely.

## Validation

- Unit tests for identity, config, transport, command handling, scripts, and FRP manager behavior.
- Integration tests against mock server protocol responses.
- `GOEXPERIMENT=jsonv2 go test ./...` in `packages/client`.
- Release artifact validation for supported packaging outputs.
