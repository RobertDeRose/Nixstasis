# Implementation Plan - Rewrite Client in Go

**Feature**: Rewrite Client in Go
**Spec**: [specs/004-rewrite-client-go/spec.md](spec.md)
**Status**: Phase 1 Complete

## Technical Context

### Architecture Overview

The `nixstasis-client` will be a single Go binary that replaces the existing shell scripts. It will be architected as a core service that manages:
1.  **Identity**: Device registration and persistence.
2.  **Plugin System**: A robust mechanism to discover, execute, and aggregate data from external binaries.
3.  **Transport**: Secure HTTP communication with the Nixstasis API.
4.  **Remote Access**: Orchestration of the `frpc` process for reverse tunneling.

The system will use a `subcommand` pattern (e.g., `nixstasis register`, `nixstasis poll`) to handle different lifecycle phases, controlled by systemd units.

### Existing Logic
- **Registration**: Currently `_api.sh` + `register`. Needs to be ported to Go structs and HTTP client.
- **Polling**: Currently `poll` script + `_api.sh`. Needs to be ported to a loop that runs plugins + core aggregation.
- **FRP**: Currently `run_frp`. Needs to be ported to `os/exec` with timeout management.
- **Data**: Currently `jq` manipulation. Needs strict Go structs for `DeviceUpdate`, `StoreInfo`, etc.

### Constraints & Patterns
- **Language**: Go (Golang) 1.21+.
- **Configuration**: YAML config file + Environment Variables (viper/koanf or stdlib).
- **Concurrency**: Plugins should run in parallel using Goroutines/Channels.
- **Serialization**: JSON for all API and Plugin communication.
- **Systemd**: Service integration is critical (notify, restart logic).

### Resolved Unknowns
- **Plugin Discovery**: Standardized on `/usr/libexec/nixstasis/plugins` (system) and `$XDG_DATA_HOME/nixstasis/plugins` (dev).
- **Schema Validation**: Client acts as a passthrough; no local schema validation to reduce complexity and coupling.
- **Update URL**: Treated as metadata reporting only; no auto-update logic in this feature scope.

## Constitution Check

### Core Principles Analysis
- **I. Quality & Simplicity**: Go offers strong typing and better error handling than Bash. Plugin system adds complexity but solves the "dynamic schema" business need. Simplicity will be maintained by keeping the core minimal.
- **II. Behavior-Driven API Testing**: BDD-style tests will be written for the *Plugin Interface* (e.g., "Given a valid plugin, When executed, Then output is merged") using standard Go testing tools.
- **III. Targeted Unit Testing**: Essential for the JSON Merge logic and Manifest parsing.
- **IV. User Experience First**: "User" here is the operator/admin. Automated registration and zero-conf (via plugins) improves UX.
- **V. Branding**: N/A (headless service).
- **VI. Performance Compliance**: Go is significantly faster than shell. Parallel plugin execution improves polling latency.

### Tech Standards Compliance
- **Language**: Constitution says "Elixir...". **DEVIATION**: This feature explicitly requests "Rewrite in Go". This is a Client-side component, whereas Elixir is likely the Server standard. We must note this deviation is intentional per user request.
- **Infrastructure**: FRP is mentioned in Constitution and Spec.

## Research Strategy

### Phase 0: Research Tasks
1.  **Plugin Discovery**: Research best practices for Linux service plugin directories (FHS compliance). (Completed)
2.  **JSON Merging**: Determine best Go library/approach for merging arbitrary JSON structures (collision handling). (Completed)
3.  **Schema Handling**: Clarify if we need to implement JSON Schema validation in the client (likely overkill for MVP, but good to know costs). (Completed)
4.  **Systemd Integration**: Best practices for Go apps (sd_notify). (Completed)

## Proposed Design

### Data Model
- `PluginManifest`: Struct for `manifest.json`.
- `DeviceIdentity`: Struct for ID storage.
- `Telemetry`: Map[string]interface{} for dynamic merging.

### Interfaces
- `PluginManager`: Discover(), ExecuteAll().
- `APIClient`: Register(), Poll().

## Implementation Steps

### Phase 1: Core Skeleton
1.  Project structure (`cmd/nixstasis`, `internal/`).
2.  Config loading.
3.  Logger setup.

### Phase 2: Identity & Registration
1.  MAC/IP detection.
2.  Registration API call.
3.  ID persistence.

### Phase 3: Plugin System
1.  Manifest parser.
2.  Execution engine (parallel).
3.  JSON Merger.

### Phase 4: Remote Access
1.  FRP wrapper (exec, timeout).
2.  Hooks to API.

### Phase 5: Packaging
1.  Makefile for `.deb` and `.tar.gz`.
