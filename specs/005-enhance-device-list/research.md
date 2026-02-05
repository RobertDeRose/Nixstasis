# Research: Enhance Device List View

**Branch**: `005-enhance-device-list` | **Date**: 2026-02-04

## Decisions & Rationale

### 1. Elixir SSH Client
**Decision**: Use Erlang's built-in **`:ssh`** application directly via a `GenServer` wrapper.
**Rationale**:
- **Interactive Shell**: Explicitly supports PTY allocation and interactive sessions (required for the Terminal tab).
- **Robustness**: Battle-tested part of OTP, supports channels and connection keep-alives natively.
- **Control**: Allows fine-grained handling of standard output/error streams to pipe directly to Phoenix Channels.
**Alternatives Considered**:
- `sshex`: Rejected because it is primarily designed for "one-off" command execution (`exec`), not persistent interactive shells.

### 2. Metrics Visualization
**Decision**: Use **ApexCharts.js** via Phoenix LiveView Client Hooks.
**Rationale**:
- **UX**: Provides smooth, client-side animations for streaming data (zooming, panning) which is critical for "real-time" feel.
- **Performance**: Use `push_event` to send small data deltas; client appends points without re-rendering the entire DOM/SVG.
- **Simplicity**: No heavy Elixir wrapper needed; configuration is simple JSON.
**Alternatives Considered**:
- `Context` (Elixir): Rejected for streaming data; re-rendering full SVGs on the server is inefficient and lacks smooth transition animations.
- `Chart.js`: Good alternative, but ApexCharts offers a slightly more modern, config-based API that fits well with LiveView hooks.

### 3. List Management
**Decision**: **Phoenix LiveView Streams**.
**Rationale**:
- **Performance**: Efficiently handles large lists by only tracking IDs on the server and appending/prepending/updating DOM elements on the client.
- **UX**: Supports real-time additions/removals (e.g., when a device comes online) naturally.
- **Consistency**: The "Phoenix Way" for handling sortable/filterable collections in 1.7+.

### 4. Terminal Integration
**Decision**: **Phoenix Channels** bridging `xterm.js` and `:ssh`.
**Rationale**:
- **Architecture**: Keeps the connection stateful on the backend (in the Channel/GenServer) while giving the frontend a standard WebSocket interface.
- **Security**: SSH credentials never leave the server; the frontend only sends keystrokes.
- **Flow**: `xterm.js` (onData) -> Channel (push "input") -> `:ssh` (send) -> `:ssh` (receive) -> Channel (broadcast "output") -> `xterm.js` (write).
