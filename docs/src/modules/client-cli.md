# Client CLI

## Language

- Go.

## Runtime Context

- Client compiled binary.
- Cobra-based CLI command tree.

## Purpose

- Provides the `nixstasis` executable for registration, polling, and script management.

## Key Files

- `packages/client/cmd/nixstasis/main.go`
- `packages/client/cmd/nixstasis/register.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/cmd/nixstasis/script.go`
- `packages/client/cmd/nixstasis/install_script.go`
- `packages/client/cmd/nixstasis/list_scripts.go`
- `packages/client/cmd/nixstasis/remove_script.go`
- `packages/client/cmd/nixstasis/test_script.go`
- `packages/client/cmd/nixstasis/repl.go`

## Public Interfaces

- CLI commands:
  - `nixstasis register`
  - `nixstasis poll`
  - `nixstasis script install <path>`
  - `nixstasis script list`
  - `nixstasis script remove`
  - `nixstasis script test`
  - `nixstasis script repl`
- Go functions:
  - `main`
  - `runMain`
  - `run`
  - `shouldSkipConfig`
  - `runRegister`
  - `runPoll`
  - `pollOnce`
  - `pollInterval`

## API Transport Configuration

- `api.url` / `NIXSTASIS_API_URL`: defaults to `https://localhost:4000`.
  Use the server's HTTPS API hostname with a trusted certificate. Userinfo,
  query strings, and fragments are not allowed in the configured base URL.
- `api.allow_loopback_http` / `NIXSTASIS_API_ALLOW_LOOPBACK_HTTP`: defaults to
  `false`. Explicitly enable it only for a local HTTP mock. It permits
  `localhost` (dialed directly as `127.0.0.1`) or loopback IP addresses and
  bypasses environment proxies. It does not permit LAN or Compose HTTP URLs.
- HTTPS always verifies certificates and hostnames. Install a private CA's public
  certificate in the OS trust store or supply a PEM CA bundle via Go's
  `SSL_CERT_FILE`. Packaged systemd services need that certificate installed in
  their OS trust store, or the variable explicitly set in a unit override.
- API redirects are not followed, including same-origin redirects. Configure the
  final API URL; neither registration bodies nor runtime credentials are
  forwarded to a redirected URL. An invalid API URL fails before registration
  sends any request.

## Installation Methods

Nixstasis publishes the managed-device client through native Linux packages,
self-extracting archives, and a Nix flake package. All supported install methods
ship the `nixstasis` CLI and an arch-matched `frpc` binary; they differ in how
files are placed and how host-level service management is handled.

### Native deb/rpm Packages

- Use `.deb` packages on Debian/Ubuntu-style hosts and `.rpm` packages on
  Fedora/RHEL-style hosts.
- Native packages install `nixstasis` to `/usr/bin/nixstasis`.
- Native packages install bundled `frpc` to `/usr/libexec/nixstasis/frpc`.
- Native packages install templates under `/usr/share/nixstasis/`.
- Package maintainer scripts seed `/etc/nixstasis/config.yaml` from
  `/usr/share/nixstasis/config.example.yaml` only when the host does not already
  have a config file.
- Native package postinstall scripts enable registration and polling units. When
  systemd is running, they also start registration and the polling path
  immediately.

### Self-Extracting `.run` Installers

- Use `.run` installers on systemd Linux hosts that do not use deb or rpm
  packages.
- Run downloaded GitHub Release installers through `sh` because release downloads
  do not preserve executable bits:

  ```sh
  sudo sh nixstasis-<version>-linux-<arch>.run
  ```

- The installer lays down the same FHS payload as the native packages:
  `/usr/bin/nixstasis`, `/usr/libexec/nixstasis/frpc`,
  `/usr/share/nixstasis/*`, `/etc/nixstasis/config.yaml` on first install, and
  systemd unit files.
- The installer overwrites binaries, unit files, and the client-owned FRP
  template at `/usr/share/nixstasis/frpc.toml` during upgrades.
- The installer preserves an existing `/etc/nixstasis/config.yaml` unless the
  operator explicitly uses the installer force-config path documented in the
  client package README.
- Inspect a `.run` payload without installing it by extracting with `--noexec`:

  ```sh
  sh nixstasis-<version>-linux-<arch>.run --noexec --target /tmp/nixstasis-installer
  ```

### Nix Flake Package

- Use the flake package for Nix-managed hosts and development validation.
- Build the client package for the current system:

  ```sh
  nix build .#client
  ```

- Build a specific supported Linux system package:

  ```sh
  nix build .#packages.x86_64-linux.client
  nix build .#packages.aarch64-linux.client
  ```

- The flake package builds the Go client with Go 1.27's standard JSON v2
  packages, vendors Go modules using a fixed-output hash, and wraps `nixstasis`
  so default FRPC paths point into the Nix store.
- The flake package places `nixstasis` under `$out/bin/nixstasis`, links bundled
  `frpc` at `$out/libexec/nixstasis/frpc`, and installs templates under
  `$out/share/nixstasis/`.
- The flake package does not mutate `/etc`, seed `/etc/nixstasis/config.yaml`, or
  install/enable systemd units. Operators using Nix must manage config and units
  with their NixOS, Home Manager, or deployment tooling.

Traceable references:

- `packages/client/README.md:136-214`
- `packages/client/build/root-dir/usr/share/nixstasis/config.example.yaml`
- `packages/client/build/root-dir/usr/share/nixstasis/frpc.toml`
- `packages/client/build/makeself/entrypoint.sh`
- `flake.nix:50-78`

## Dependencies

### Internal

- `internal/config`
- `internal/logging`
- `internal/identity`
- `internal/transport`
- `internal/script`
- `internal/frp`
- `internal/commands`
- `internal/telemetry`

### External

- `github.com/spf13/cobra`
- `github.com/spf13/viper`
- Go `runtime/trace` flight recorder.

## Client-Server Interaction Details

- `register` calls the transport client registration endpoint.
- `poll` sends telemetry heartbeats, processes server commands, sends command results, and starts/stops FRPC based on the heartbeat response.

Traceable references:

- `packages/client/cmd/nixstasis/main.go:20-98`
- `packages/client/cmd/nixstasis/register.go:16-93`
- `packages/client/cmd/nixstasis/poll.go:21-249`
- `packages/client/cmd/nixstasis/script.go:5-12`
