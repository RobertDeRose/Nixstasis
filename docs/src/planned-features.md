# Planned Features

## Project Overview

Nixstasis needs a development-laptop runtime that exercises the same remote-access
boundaries operators rely on in deployment. Local development must be able to test
dynamic TLS approval and browser-driven SSH terminal flows without waiting for a
production-like environment.

## Goals

- Provide a repeatable development-laptop environment for end-to-end remote-access
  validation.
- Make Caddy on-demand TLS approval testable from local development workflows.
- Make UI-launched SSH terminal sessions testable from local development workflows.
- Keep the development workflow aligned with documented runtime boundaries for
  Phoenix, Caddy, FRPS, FRPC, and managed-device identity.
- Support an optional public-fidelity mode using DuckDNS or a real operator-owned
  domain when developers need to validate public ACME behavior.

## Non-Goals

- Replacing the supported production Compose deployment path.
- Changing production TLS policy or public ingress requirements.
- Building a full hosted staging environment.
- Making local development depend on public DNS or public certificate issuance when
  a local equivalent can validate the same application behavior.
- Requiring ngrok, localtunnel, or another third-party tunnel provider for the
  default development workflow.

## Global Constraints

- The supported production deployment path remains `deploy/compose`.
- Development overrides should use Compose file composition, not mutable release
  image tags in `.env`.
- The Phoenix application remains public only through Caddy in deployment-shaped
  flows.
- SSH terminal testing must exercise the browser UI, Phoenix Channels, server-side
  SSH process boundary, and FRP TCP mux path rather than bypassing them with direct
  shell access.
- TLS testing must exercise `GET /api/v1/check_domain` approval behavior.
- Default laptop mode uses Caddy's internal CA/local certificates and local host
  routing so development does not require public DNS or public ingress.
- Optional public-fidelity mode may use DuckDNS or a real domain with DNS-based
  ACME validation to test publicly trusted certificate behavior.

## Cross-Cutting Decisions

- Treat local dynamic TLS and UI SSH validation as one development-environment
  feature because both depend on the same local ingress, DNS/host routing, FRPS,
  and device-client simulation shape.
- Default development mode uses local-only trust and routing mechanisms instead of
  public DNS or real public certificate issuance.
- DuckDNS or a real domain is an optional validation path for public ACME fidelity,
  not a prerequisite for local feature development.
- Keep production Compose docs and development-laptop docs explicitly separated so
  test affordances do not become accidental production guidance.

## Resolved Questions

- The managed test device runs as a containerized client with systemd, sshd, frpc,
  and the Go client binary — matching real device lifecycle.
- Reserved local hostnames: `nixstasis.localhost`, `auth.localhost`,
  `frp-admin.localhost`, and `atom-<normalized-device-id>.localhost`.
- Terminal smoke test covers session open, command execution, session close, and
  reopen via ExUnit LiveView integration test with a fake SSH client.
- DuckDNS support is documented as optional manual setup guidance; no DNS-provider
  abstraction was added.

## Feature Map

### `dev-laptop-remote-access`

- Status: delivered
- Overview:
  - Create a default development-laptop workflow that can run the server-side stack,
    register or simulate a managed client, validate Caddy dynamic TLS approval with
    local certificates, and open SSH terminal sessions from the Phoenix UI through
    the FRP path. Add optional guidance for DuckDNS or a real domain when public
    ACME fidelity is required.
- Requirements:
  - Provide documented startup and teardown commands for the local development
    environment.
  - Provide local host routing/DNS guidance for the app host, AuthCrunch host,
    FRPS admin host, and device wildcard hostnames.
  - Provide a local TLS validation path that exercises Caddy on-demand approval via
    Phoenix `GET /api/v1/check_domain` using Caddy internal CA/local certificates
    by default.
  - Provide optional DuckDNS or real-domain guidance for validating public ACME
    behavior without making that path required for normal development.
  - Provide a test managed-device path that can register, connect FRPC to FRPS, and
    expose SSH in a way the UI terminal can reach.
  - Provide validation steps for opening a terminal from `/devices/:id` and running
    a harmless command through the browser UI.
  - Document how the development workflow differs from production Compose.
- Constraints:
  - Must not weaken or bypass production ingress/authentication requirements.
  - Must not require public DNS or public internet exposure for the core local
    validation path.
  - Must keep DuckDNS and real-domain support optional and clearly marked as
    public-fidelity validation.
  - Must preserve Compose-file-composition as the development override mechanism.
  - Must keep generated certificates, local keys, and runtime state out of source
    control.
- Non-goals:
  - Making production certificate issuance validation mandatory for local
    development.
  - Multi-user staging operations.
  - Load, performance, or HA validation.
  - Replacing existing E2E API protocol validation.
- Success criteria:
  - A developer can start the local stack from a clean checkout using documented
    commands and local-only configuration.
  - Visiting the local app through Caddy with local certificates causes TLS approval
    behavior to be exercised and observable.
  - Optional DuckDNS or real-domain instructions identify how to run a higher
    fidelity public ACME validation path and how it differs from default laptop
    mode.
  - A test device appears in the UI with remote-access state sufficient to launch
    a terminal.
  - A browser-launched terminal session can run a harmless command through FRP and
    SSH without direct shell shortcuts.
  - The docs clearly separate development-only shortcuts from production deployment
    guidance.
- Risks and tradeoffs:
  - Local TLS can become misleading if it validates only certificate plumbing and
    not domain approval behavior.
  - Device simulation can hide real packaging/client defects if it bypasses the Go
    client and FRPC process model.
  - Hostname routing can become fragile across macOS, Linux, Docker, Podman, and
    Apple Container unless the spec chooses supported paths explicitly.
  - Using real public DNS would increase fidelity but adds cost, secrets, and
    operational burden for developers.
  - DuckDNS reduces domain cost but adds account tokens, DNS propagation delay, and
    external-service availability concerns.
  - Tunnel providers such as ngrok or localtunnel are useful for reachability demos
    but can mask Caddy-owned TLS behavior if they terminate TLS before Caddy.
- Dependencies:
  - `deploy/compose/docker-compose.yml`
  - `deploy/compose/caddy/Caddyfile`
  - `deploy/compose/frps/frps.toml`
  - `packages/server/lib/nixstasis_web/controllers/tls_controller.ex`
  - `packages/server/lib/nixstasis_web/channels/terminal_channel.ex`
  - `packages/server/lib/nixstasis/devices/ssh_client.ex`
  - `packages/client/internal/frp/manager.go`
  - `packages/client/cmd/nixstasis/register.go`
  - `packages/client/cmd/nixstasis/poll.go`
- Suggested validation:
  - Static validation for generated Compose development overrides.
  - A local smoke test that confirms Caddy reaches Phoenix TLS approval.
  - A local smoke test that confirms Caddy serves local certificates through the
    default laptop hostnames.
  - A local smoke test that confirms FRPC connects to FRPS using the development
    configuration.
  - Optional DuckDNS or real-domain validation that documents certificate issuance,
    DNS challenge behavior, and expected failure modes.
  - A browser/UI or E2E journey that launches a terminal and executes a harmless
    command through SSH.
- Suggested first workflow command: `/start-feature dev-laptop-remote-access`

### `self-extracting-installer`

- Status: in-spec
- Overview:
  - Build a CI-produced self-extracting installer archive for non-Nix, non-deb,
    non-rpm installs. The archive bundles the client binary, arch-matched `frpc`,
    configs, systemd units, and an artifact manifest into a single `.run` file
    that extracts and installs to FHS paths.
- Requirements:
  - Produce a self-extracting archive per supported architecture as part of the
    client release workflow.
  - Include an install script that copies files to `/usr/bin/`,
    `/usr/libexec/nixstasis/`, `/etc/nixstasis/`,
    `/usr/share/nixstasis/`, and `/lib/systemd/system/`.
  - Include an `artifacts.json` manifest with version, arch, sha256 per file,
    file modes, and build timestamp.
  - Consume `frpc` from `packages/frp` via the shared acquisition path, not a
    separate download.
  - Extend client release CI so `.run` files are produced and verified alongside
    existing archives, `.deb`, and `.rpm` packages.
  - Extend `verify_artifacts.sh` to validate `.run` archive contents and
    manifest integrity.
- Constraints:
  - Do not embed `frpc` in the Go client binary.
  - `FRPS_SERVER_ADDR` remains a runtime env var, not baked into the archive.
  - Systemd units must use `PrivateTmp=true`.
  - `build/root-dir` stays as the GoReleaser staging source.
  - `packages/frp` remains the shared source of truth for FRP version and
    checksums.
- Non-goals:
  - Replacing `.deb` or `.rpm` packaging for distros that support them.
  - Interactive TUI installer or configuration wizard.
  - Automatic service enablement or start on install.
  - Uninstall support.
- Success criteria:
  - A `.run` file for each release architecture is published to GitHub Releases.
  - Running the `.run` file on a clean Linux system installs all required files
    to their FHS paths.
  - Existing `/etc/nixstasis/frpc.toml` and `/etc/nixstasis/config.yaml` files are
    preserved on upgrade unless the installer is explicitly forced to replace
    them.
  - `artifacts.json` in the archive matches the installed bundle contents by
    sha256.
  - `verify_artifacts.sh` catches content or manifest drift in CI.
- Risks and tradeoffs:
  - `makeself` adds a release CI dependency.
  - Self-extracting archives are less auditable than plain tarballs, so the
    installer must support no-exec extraction for inspection.
  - Install script upgrade behavior must avoid overwriting operator-owned config.
- Dependencies:
  - `packages/frp/bin/download_frp.sh`
  - `packages/client/scripts/fetch_frpc.sh`
  - `.github/workflows/release_client.yml`
  - `packages/client/scripts/release/verify_artifacts.sh`
  - `packages/client/build/root-dir/`
  - `prod.env`
- Suggested validation:
  - CI step that builds the `.run` archive from snapshot artifacts and verifies
    extraction plus manifest integrity.
  - Fresh-install and upgrade tests for file placement, modes, and config
    preservation.
  - Manual smoke test on Alpine or Arch to confirm FHS placement without
    `dpkg`/`rpm`.
- Suggested first workflow command: `/start-feature self-extracting-installer`
