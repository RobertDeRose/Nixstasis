# Nixstasis Client (Go)

The Nixstasis client is a lightweight IoT monitoring agent written in Go. It replaces the original Bash prototype and
now provides embedded Starlark scripting for telemetry, durable identity, and FRP tunnel control.

## Features

- **Auto-Registration**: Registers with the Nixstasis server on first boot and persists a device UUID.
- **Starlark Scripts**: Discovers and runs `stary` scripts to collect telemetry.
- **Remote Access**: Manages `frpc` tunnels on-demand based on server directives.
- **Resilient**: Handles network interruptions and retries automatically.

## Project Layout

- `cmd/nixstasis`: Source directory for the `nixstasis` CLI (`register`, `poll`, etc.).
- `internal`: Core packages (config, identity, transport, telemetry, script, frp).
- `bin`: Packaging scripts and helper utilities.

## Building

### Prerequisites

- Go 1.26+
- mise

### Commands

```bash
mise run build      # Build binary locally (bin/nixstasis)
mise run build:local # Run the client CLI locally
mise run test       # Run unit tests with race detector and coverage
mise run test:coverage # Print coverage summary from coverage.out
```

## Usage

```bash
bin/nixstasis register
bin/nixstasis poll
```

## E2E Testing

The client includes a lightweight E2E harness for validating client/server integration.
An entire suite of journeys can be run like the following:

```bash
scripts/e2e/run --suite full --env local --trigger manual --protocol-version 1
scripts/e2e/run --suite full --env local --trigger manual --protocol-version 1 --idempotency-key local-full-001
scripts/e2e/run --suite runtime --env local --trigger manual --protocol-version 1
scripts/e2e/run --suite runtime_step_labels --journey runtime_step_labels --env local --trigger manual --protocol-version 1
```

An individual journey can be like the following:

```bash
scripts/e2e/run --journeys auth,dashboard --env local --protocol-version 1
scripts/e2e/run --journey auth --env local --protocol-version 1
```

To aid in creating new suites of end-to-end tests, there is a scaffolding script:

```bash
scripts/e2e/scaffold --id disk_pressure --suite runtime --description "Validate disk pressure telemetry and alerting" \
--steps \
"register_device:device_registered,"\
"poll_with_scripts:poll_applied,"\
"verify_alert:alert_triggered,"\
"cleanup:resources_cleaned"
```

To see what the scaffold will do without doing it, there is a `--dry-run` flag

```bash
scripts/e2e/scaffold  --dry-run --id runtime_disk_pressure --steps register_device:device_registered
```

```bash
# optional custom step labels (only when needed):
scripts/e2e/scaffold --id runtime_disk_pressure --steps register_phase=register_device:device_registered
```

Configuration lives in `scripts/e2e/config.example.yaml` and can be customized per environment. The CLI posts runs and
results to the server; use the printed `RunID` to query `/e2e/runs/:id`, `/e2e/runs/:id/results`, and
`/e2e/runs/:id/results/:journey_id/log`.

For local runtime E2E, keep `e2e.base_domain` aligned with the server's dev/test base domain. The default local value
is `devices.example.com`.

Journey logs are JSONL records in schema `e2e_log.v1`:

- journey start envelope with run metadata
- one terminal step record per action (`passed|failed`) with `duration_ms`
- journey completion summary with step totals and failure metadata

The runtime suite generates and executes 10+ Linux-oriented Starlark scripts (real `exec_cmd` usage) and validates:

- runtime API contracts (`register`, `heartbeat`, `command_payloads`, `command_results`, `check_domain`)
- telemetry persistence and report queryability
- alert triggering from script data

Production `exec_cmd` usage is deny-by-default. Operators must explicitly
allowlist commands in the client runtime configuration before scripts can run
host commands.

Runtime suite journeys:

- `runtime_linux_telemetry` (full telemetry/report/alert flow)
- `runtime_transport_contract` (transport endpoint parity + command payload/result lifecycle)
- `runtime_transport_negative` (transport negative-path assertions for 404/400 behavior)

On non-Linux hosts, `scripts/e2e/run` automatically runs runtime E2E in an ephemeral Ubuntu container using Apple
Container first, then Docker, then Podman. The script rewrites the API host for the selected runtime automatically.

## Configuration

Configuration is loaded from `/etc/nixstasis/config.yaml`.

```yaml
api:
  url: "https://nixstasis.example.com" # Public Caddy host for the Nixstasis server

poll:
  interval: 10s

scripts:
  dir: "/usr/libexec/nixstasis/scripts"
```

For Compose dev-harness remote-access validation, use the dev-lab script at
`deploy/compose/scripts/dev-lab.sh` from the repository root. It starts the full
stack including a containerized client that runs the real Go client binary with
systemd, sshd, and frpc — matching real device lifecycle. Scale client containers
with `--clients N`.

## Packaging

GoReleaser is the supported client release path for archive, `.deb`, and `.rpm` outputs. Release CI also builds
self-extracting `.run` installers for systemd Linux hosts that do not use deb or rpm packages.

1. Review the shared production version pins:

```bash
grep -E '^(FRP_VERSION|CADDY_VERSION|POSTGRES_VERSION)=' ../../prod.env
```

1. Build snapshot artifacts from `packages/client`:

```bash
goreleaser release --snapshot --clean
```

1. Verify deliverables and release naming:

```bash
./scripts/release/verify_artifacts.sh
```

The generated archive and native packages install these client assets:

- `nixstasis` at `/usr/bin/nixstasis`
- bundled `frpc` at `/usr/libexec/nixstasis/frpc`
- config template at `/usr/share/nixstasis/config.example.yaml`
- systemd units `nixstasis-registration.service`, `nixstasis-poll.service`, and `nixstasis-poll.path`

On package install, the maintainer script seeds `/etc/nixstasis/config.yaml`
from the example template if the host does not already have one.

The self-extracting installer contains the same assets plus an `install.sh`
script and an `artifacts.json` manifest. It requires a running systemd host.
Run it as root:

```bash
sudo ./nixstasis-<version>-linux-<arch>.run
```

The installer overwrites binaries, systemd units, and the client-owned FRP
template at `/usr/share/nixstasis/frpc.toml`. It preserves existing
`/etc/nixstasis/config.yaml` and seeds it from the example template on fresh
installs. Use `--force-config` to replace the existing config file:

```bash
sudo ./nixstasis-<version>-linux-<arch>.run -- --force-config
```

To inspect the installer without running it:

```bash
sh ./dist/makeself/nixstasis-installer/linux<arch>/nixstasis-<version>-linux-<arch>.run --noexec --target /tmp/nixstasis-installer
```

Do not use `bash -n` or `sh -n` as an installer integrity check. A makeself
installer is a shell stub with appended archive bytes, so shell syntax checkers
can report false heredoc errors after the script payload boundary. Use
`mise release:verify` to extract and validate the payload.

The `.run` installer removes GoReleaser's makeself support files
(`postinstall.sh` and `package.lsm`) after a normal install. They can still
appear when inspecting with `--noexec` because makeself disables cleanup in that
mode.

The bundled FRP client template sets
`serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`; the packaged client injects that
from `frp.server_addr` in `/etc/nixstasis/config.yaml`. FRP authentication uses
the `remote_access_token` returned by the server heartbeat response and passes
it to the transient FRPC unit as the `FRPS_AUTH_TOKEN` systemd credential.
`frp.auth_token` is not the normal remote-access token source. Device subdomains are requested under
`atom-<normalized-device-id>.<base-domain>` unless `frp.name` is explicitly set
as an override.

For local-only packaging experiments, you can still override the bundled binary:

```bash
export FRPC_SOURCE_BINARY=/absolute/path/to/frpc
export FRPC_SOURCE_SHA256=<sha256>
goreleaser release --snapshot --clean
```

## Rewrite Status

From `docs/src/features/go-client-rewrite/tasks.md`, the Go rewrite is largely complete. Remaining items:

- T027: FRP lifecycle hooks for connection metadata
