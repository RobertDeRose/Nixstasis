# Nixstasis Client (Go)

The Nixstasis Client is a lightweight IoT monitoring agent written in Go. It replaces the original Bash prototype and
now provides embedded Starlark scripting for telemetry, durable identity, and FRP tunnel control.

## Features

- **Auto-Registration**: Registers with the Nixstasis server on first boot and persists a device UUID.
- **Starlark Scripts**: Discovers and runs `stary` scripts to collect telemetry.
- **Remote Access**: Manages `frpc` tunnels on-demand based on server directives.
- **Resilient**: Handles network interruptions and retries automatically.

## Project Layout

- `cmd/nixstasis`: CLI entry point (`register`, `poll`, etc.).
- `internal`: Core packages (config, identity, transport, telemetry, script, frp).
- `bin`: Packaging scripts and helper utilities.

## Building

### Prerequisites

- Go 1.25+
- Make

### Commands

```bash
make build    # Build binary locally (bin/nixstasis)
make install  # Used by `pre_package.sh` for Debian package
make test     # Run unit tests
make lint     # Run linters and formatters
```

## Usage

```bash
bin/nixstasis register
bin/nixstasis poll
```

## Configuration

Configuration is loaded from `/etc/nixstasis/config.yaml`.

```yaml
api:
  url: "http://localhost:4000" # Nixstasis Server URL

poll:
  interval: 10s

scripts:
  dir: "/usr/libexec/nixstasis/scripts"
```

## Packaging

This project uses a custom packaging framework.

1. `bin/pre_package.sh` prepares the `build/root-dir` with artifacts (binary, config, service).
2. The GitHub Actions workflow invokes this script defined in `package_options.yml` before building the Debian package.

## Rewrite Status

From `specs/004-rewrite-client-go/tasks.md`, the Go rewrite is largely complete. Remaining items:

- T027: FRP lifecycle hooks for connection metadata
