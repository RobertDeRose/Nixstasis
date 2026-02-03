# Research Summary - Rewrite Client in Go

**Status**: Phase 0 Complete
**Date**: 2026-02-02

## Decisions

### 1. Plugin Architecture
- **Decision**: Adopt a "Sidecar Executable" pattern where plugins are standalone binaries discovered via the filesystem.
- **Discovery Path**: Following FHS compliance (Research item 1):
  - **System**: `/usr/libexec/nixstasis/plugins` (packaged plugins)
  - **Admin**: `/usr/local/lib/nixstasis/plugins` (custom plugins)
  - **Dev/User**: `$XDG_DATA_HOME/nixstasis/plugins` (local dev)
- **Rationale**: Keeps the core client stable and strictly separated from plugin runtime crashes. Allows plugins to be written in any language (Go, Python, Shell) as long as they output JSON to stdout.

### 2. JSON Merging Strategy
- **Decision**: Use `map[string]interface{}` aggregation with a "Last Write Wins" policy for top-level keys, but "Deep Merge" for nested objects where possible.
- **Library**: `dario.cat/mergo` (Research item 2) for struct-based merging if we define a loose schema, or custom map traversal for dynamic payloads. Given the requirement for "dynamic schema", we likely need the dynamic map approach.
- **Conflict Resolution**: If two plugins provide the same key (e.g., `temperature`), the core client will log a warning and overwrite with the last plugin's value (determined by lexicographical sort of plugin names for determinism).

### 3. Systemd Integration
- **Decision**: Use `github.com/coreos/go-systemd/v22/daemon` for native notifications.
- **Features**:
  - `READY=1`: Sent after config load and plugin discovery.
  - `WATCHDOG=1`: Heartbeat thread in the main loop.
  - `STOPPING=1`: On SIGTERM.
- **Rationale**: Essential for high availability in an IoT fleet context.

### 4. Project Structure
- **Decision**: Standard Go Layout with Cobra.
- **Structure**:
  ```text
  cmd/nixstasis/
    main.go
    root.go
    register.go
    poll.go
  internal/
    plugin/     # Plugin manager
    identity/   # Registration logic
    transport/  # HTTP/MQTT clients
    frp/        # Remote access wrapper
  ```

## Alternatives Considered

- **Go Plugins (`plugin` package)**: Rejected. Too brittle (requires exact Go version match), doesn't support non-Go plugins.
- **HashiCorp `go-plugin` (gRPC)**: Rejected. Overkill for "stdout JSON" requirement. Adds complexity and dependency weight.
- **Embedded Scripts (Lua/JS)**: Rejected. User explicitly requested "executable" plugins.

## Open Questions Resolved

- **Plugin Discovery**: `/usr/libexec/nixstasis/plugins` + `/var/lib/nixstasis/plugins` (writable).
- **Schema Validation**: Client will *not* validate plugin output against the schema URL. It blindly forwards the merged JSON. Server-side validation is assumed.
- **Update URL**: Client treats this as metadata to report to the server. Actual update mechanism is out of scope (likely handled by separate apt/package flow or future feature).
