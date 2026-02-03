# Nixstasis Client (Go Implementation)

The Nixstasis Client is a lightweight IoT monitoring agent written in Go. It collects system telemetry via plugins and
manages remote access tunnels using `frp`.

## Features

- **Auto-Registration**: Automatically registers with the Nixstasis server on first boot.
- **Plugin System**: Executes external plugins (scripts/binaries) to collect data.
- **Remote Access**: Manages `frpc` tunnels on-demand.
- **Resilient**: Handles network interruptions and restarts automatically.

## Building

### Prerequisites

- Go 1.21+
- Make

### Commands

```bash
make build    # Build binary locally (bin/nixstasis)
make install  # Used by `pre_package.sh` for Debian package
make test     # Run unit tests
make lint     # Run linters and formatters
```

## Packaging

This project uses a custom packaging framework.

1. `bin/pre_package.sh` prepares the `build/root-dir` with artifacts (binary, config, service).
2. The GitHub Actions workflow invokes this script defined in `package_options.yml` before building the Debian package.

## Configuration

Configuration is loaded from `/etc/nixstasis/config.yaml`.

```yaml
api:
  url: "http://localhost:4000" # Nixstasis Server URL

poll:
  interval: 10s

plugins:
  dir: "/usr/libexec/nixstasis/plugins"
```
