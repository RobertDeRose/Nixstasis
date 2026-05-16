# Feature Specification: Rewrite Client in Go

**Feature Branch**: `004-rewrite-client-go` **Created**: 2026-02-02 **Status**: Draft **Input**: User description: "Rewrite the client located in `packages/client` in Go"

## Clarifications

### Session 2026-02-02
- Q: The existing implementation uses separate bash scripts. FR-001 allows for a 'single binary or CLI suite'. Which architecture do you prefer for the Go rewrite? → A: Option A (Recommended) - Single Binary with Subcommands (e.g., nixstasis register, nixstasis poll)
- Q: FR-008 mentions configuration via environment variables or a config file. Which should be the primary configuration method? → A: Option A (Recommended) - Use a configuration file (e.g., config.yaml) as primary, with ENV overrides
- Q: The current build process generates a Debian package structure. How should the new Go binary be packaged? → A: Option C - Both .deb and .tar.gz
- Q: How should the client manage the `frpc` dependency? → A: Option A (Recommended) - Client expects `frpc` to be pre-installed in system PATH

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.
-->

### User Story 1 - Device Identity & Registration (Priority: P1)

As a Device Administrator, I need the device to automatically register itself with the Nixstasis server upon first boot, so that it can be identified and managed remotely without manual provisioning.

**Why this priority**: Without registration, the device has no identity (UUID) and cannot communicate with the server for any other functions.

**Independent Test**: Can be tested by deleting the local ID file and restarting the service. The device should successfully negotiate a new ID with the server.

**Acceptance Scenarios**:

1. **Given** a device with no local `/etc/nixstasis/id` file, **When** the client application starts, **Then** it detects the MAC address (from eth0) and IP address.
2. **Given** valid device identity data, **When** the client posts to `/device/register`, **Then** it receives a valid UUID.
3. **Given** a received UUID, **When** the registration completes, **Then** the UUID is persisted to disk at `/etc/nixstasis/id`.
4. **Given** network unavailability, **When** registration fails, **Then** the application retries or exits with a standard error code (triggering systemd restart).

---

### User Story 2 - Plugin-Based Telemetry Polling (Priority: P1)

As an Operations Manager, I need the device to run product-specific plugins to collect telemetry, so that different products can report custom data schemas without modifying the core client.

**Why this priority**: Supports the new dynamic schema requirement for different products.

**Independent Test**: Create a dummy executable that outputs valid JSON to stdout and a manifest.json. Verify the client runs it and includes the output in the payload.

**Acceptance Scenarios**:

1. **Given** a registered plugin with a valid `manifest.json` and executable, **When** the polling interval triggers, **Then** the client executes the plugin's binary.
2. **Given** multiple registered plugins, **When** polling occurs, **Then** the client runs them (potentially in parallel) and merges their JSON output into a single payload.
3. **Given** a plugin that outputs invalid JSON or fails, **When** polling, **Then** the client logs the error and excludes that plugin's data but continues with others.
4. **Given** a plugin manifest with a schema URL, **When** the plugin registers, **Then** the client submits this schema URL to the server (if part of the registration/heartbeat protocol).

---

### User Story 3 - Remote Access Control (Priority: P2)

As a Support Engineer, I need the device to establish a reverse tunnel (FRP) when requested by the server, so that I can troubleshoot issues remotely.

**Why this priority**: Essential for maintenance but secondary to basic monitoring.

**Independent Test**: Can be tested by forcing the mock API to return a non-empty `remote_access_token`.

**Acceptance Scenarios**:

1. **Given** a poll response containing a non-empty `remote_access_token`, **When** the tunnel is not currently running, **Then** the client starts the FRP process (frpc) with that token.
2. **Given** the tunnel starts, **When** the connection is established, **Then** the client immediately notifies the server with the connection string.
3. **Given** a running tunnel, **When** the process exceeds the 1-hour hard timeout, **Then** the client terminates the process to prevent stale connections.
4. **Given** the tunnel stops (gracefully or forcefully), **When** it terminates, **Then** the client notifies the server to clear the connection string.

### Edge Cases

- **Plugin Hangs**: If a plugin executable hangs, the client must time it out (e.g., 5s) and not block the main loop.
- **JSON Merge Conflicts**: If two plugins output the same top-level key, the merge strategy should be defined (e.g., last one wins, or error).
- **Network Flapping**: If the API is unreachable during a poll, the system should log the error and retry on the next interval without crashing.
- **Corrupt ID File**: If `/etc/nixstasis/id` exists but is empty or invalid, the system should treat it as missing and re-register.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST be implemented as a Go application (single binary with subcommands like `nixstasis register`, `nixstasis poll`) replacing the existing Bash scripts.
- **FR-002**: The system MUST identify the device using the MAC address of `eth0` and generate a unique name in the format `atom-<mac_stripped_lowercase>`.
- **FR-003**: The system MUST persist the assigned Device UUID to `/etc/nixstasis/id` and read it on startup.
- **FR-004**: The system MUST support a plugin architecture where plugins are defined by a `manifest.json` containing:
    - Version
    - Update URL
    - Schema Definition URL
    - List of executables to run
- **FR-005**: The system MUST execute plugin binaries and capture their STDOUT (expected to be JSON).
- **FR-006**: The system MUST merge JSON output from all successful plugins into the final telemetry payload.
- **FR-007**: The system MUST aggregate core data (if any) along with plugin data:
    - Network Interfaces (IP/MAC)
    - Tunnel Status (FRP running state)
- **FR-008**: The system MUST communicate with the Nixstasis API via HTTP/JSON, handling errors and retries gracefully.
- **FR-009**: The system MUST manage the lifecycle of the `frpc` binary for remote access, including:
    - Starting the process when requested.
    - Enforcing a maximum execution time (default 1 hour).
    - Sending lifecycle hooks (Start/Stop) to the API to update connection details.
    - **Constraint**: The client expects `frpc` to be pre-installed in the system PATH.
- **FR-010**: The system MUST support configuration via a configuration file (e.g., `config.yaml`) as the primary method, with support for environment variable overrides.
- **FR-011**: The build system MUST produce both a Debian package (`.deb`) and a static binary archive (`.tar.gz`).

### Key Entities *(include if feature involves data)*

- **DeviceIdentity**: Contains MAC, IP, Name, and UUID.
- **PluginManifest**: Defines version, URLs, and executables for a plugin.
- **TelemetryPayload**: Merged JSON object from all plugins + core data.
- **ConnectionStatus**: Contains the remote access token and connection string (FRP URL).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The Go client successfully registers a new device and persists the ID.
- **SC-002**: The client maintains a stable polling loop (default 10s) with < 1% failure rate for valid network conditions.
- **SC-003**: Plugins can register and have their output included in the payload within 1 polling cycle of installation.
- **SC-004**: The client handles a hanging plugin gracefully (timeout) without crashing the main service.
- **SC-005**: The compiled binary replaces the functionality of ~500 lines of Bash with type-safe, maintainable Go code.
