# Compose Dev Harness

## Feature Name

`compose-dev-harness`

## Goal

Provide a repeatable Compose development harness that can validate the Nixstasis
remote-access stack without a public domain by default. The workflow must run the
server-side stack, exercise Caddy dynamic TLS approval with local certificates,
register or simulate a managed device, connect FRPC to FRPS, and launch an SSH
terminal from the Phoenix UI through the FRP path.

Optional public-fidelity validation may use DuckDNS or a real operator-owned
domain to test DNS-based ACME behavior, but that path must not be required for
normal development.

## Source Of Intent

- `docs/src/planned-features.md`, feature `compose-dev-harness`
- `docs/src/runtime-boundaries.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/modules/server-web.md`

## Users

- Developers validating remote-access behavior from a laptop.
- Maintainers reviewing TLS approval and terminal regressions before release.
- Operators who need clear separation between local validation and production
  deployment guidance.

## Requirements

- Provide documented startup and teardown commands for a default laptop mode.
- Default laptop mode must use local host routing and Caddy internal CA/local
  certificates rather than public DNS or public certificate issuance.
- Default laptop mode must exercise Caddy on-demand approval through Phoenix
  `GET /api/v1/check_domain`.
- Provide a managed test-device path that starts PCP services, registers with the
  server, runs or simulates FRPC, and exposes SSH through FRP so the UI terminal
  can connect.
- Provide validation steps for opening a terminal from `/devices/:id` and running
  a harmless command through the browser UI.
- Provide optional public-fidelity guidance for DuckDNS or a real domain using
  DNS-based ACME validation.
- Clearly separate development-only shortcuts from production Compose guidance.

## Constraints

- Do not weaken production ingress or authentication requirements.
- Do not require public DNS, public ingress, ngrok, localtunnel, or similar tunnel
  providers for default laptop mode.
- Preserve Compose-file composition as the development override mechanism.
- Keep generated certificates, local keys, DNS tokens, and runtime state out of
  source control.
- The Phoenix app remains reached through Caddy in deployment-shaped flows.
- SSH terminal validation must exercise the browser UI, Phoenix Channels,
  server-side SSH process boundary, and FRP TCP mux path.

## Non-Goals

- Replacing the supported production Compose deployment path.
- Making production Let's Encrypt validation mandatory for local development.
- Building a hosted staging environment.
- Load, performance, or high-availability validation.
- Replacing existing E2E API protocol validation.

## Proposed Design

### One-Command Dev Lab

The fastest local path is a single-command dev lab (`mise run deploy:dev -- up
--clients N`) that starts the server stack and runs N managed client containers.
The dev lab inspects the runtime MAC addresses, pre-approves those rows after the
server is ready, and the Go clients still complete registration and polling with
issued credentials. The dev lab uses a tracked `dev.env` with hardcoded
development defaults (no template secrets), uses `NIXSTASIS_FORCE_SSL=false`, and
the Compose development harness with `docker compose --env-file dev.env`.

### Default Laptop Mode

Default laptop mode is local-first and deterministic:

- Use a single `docker-compose.yml` with environment-file-driven configuration.
- Run Phoenix, Caddy, FRPS, PostgreSQL, and client containers using the same
  compose file with `docker compose --env-file dev.env`.
- Use Caddy local certificates or internal CA for HTTPS.
- Use local host routing for reserved app hosts and device wildcard hosts.
- Use Caddy's internal CA directly for deterministic laptop HTTPS; production
  on-demand TLS still validates domains through the Phoenix ask endpoint.
- Run a test device using a containerized client with systemd, sshd, frpc, and
  the Go client binary — matching real device lifecycle.
- The client container acts as both the Go client and the SSH target reachable
  through FRP.
- The client image entrypoint writes `/etc/nixstasis/config.yaml` from Compose
  environment before systemd starts so registration and polling use the local
  Compose service names.
- Set `NIXSTASIS_FORCE_SSL=false` so Phoenix does not enforce SSL redirects in
  local mode.

### Optional Public-Fidelity Mode

Public-fidelity mode should be documented as a separate validation path:

- DuckDNS may be used for low-cost DNS and TXT-record ACME challenge testing.
- A real operator-owned domain may be used when available.
- DNS provider credentials must stay outside source control.
- Public-fidelity mode validates DNS challenge behavior and public certificate
  issuance, but it does not replace default laptop mode.

### Hostnames

Default laptop mode reserves these local hostnames:

- `nixstasis.localhost` for the Phoenix app through Caddy.
- `auth.localhost` for AuthCrunch through Caddy.
- `frp-admin.localhost` for the FRPS dashboard through Caddy.
- `atom-<normalized-device-id>.localhost` for device HTTP routes through FRPS and
  Caddy.

These names intentionally mirror the existing production reserved-host pattern of
`nixstasis.<base-domain>`, `auth.<base-domain>`, `frp-admin.<base-domain>`, and
wildcard device hosts while keeping default routing local-only. Scripts, examples,
and validation steps must reuse these names consistently.

### Managed Test Device

The managed-device path uses a containerized client that runs Ubuntu with systemd
as PID 1, sshd for remote access, frpc for tunnel connectivity, and the Go client
binary started via systemd units. This matches the real device lifecycle including
registration, polling, FRPC process management, and SSH key authorization. Scale
client containers with `--clients N` or `docker compose --scale client=N`.
For HTTP-route validation, the dev env enables a simulator-local HTTPS endpoint
on `127.0.0.1:443`; wildcard device requests then traverse Caddy, FRPS, FRPC,
and an actual client-local TLS listener instead of stopping at proxy
registration.
Because application logs are owned by systemd services, diagnostics read journald
inside the container rather than Docker stdout.

### TLS Observation Diagnostics

A development-only TLS observation system records Caddy ask calls in an
ETS-backed GenServer (`Nixstasis.TLSObservations`). Observations are exposed via
`/_nixstasis/laptop/tls_observations` (GET to list, DELETE to clear) and gated by
`NIXSTASIS_TLS_OBSERVATIONS_ENABLED` (routed through `runtime.exs` into app
config) and `NIXSTASIS_TLS_OBSERVATIONS_TOKEN`. The observation store is capped at
50 entries and is not persisted. Validation scripts use this endpoint to
programmatically confirm Caddy reached Phoenix for domain approval.

### Terminal Smoke Coverage

The minimum terminal smoke test must launch the terminal from `/devices/:id`, run a
harmless command such as `whoami`, `sudo systemctl status nixstasis-poll.service`,
or `printf nixstasis-smoke`, close the session, and reopen a terminal for the same test device. This is implemented as an ExUnit
LiveView integration test using a fake SSH client, covering command execution and
session lifecycle behavior without requiring a running FRP tunnel or browser
automation.

### Public-Fidelity Guidance

DuckDNS and real-domain public-fidelity support should be documented as optional
manual setup guidance for this feature. Do not add a DNS-provider abstraction until
there is a concrete implementation need beyond documenting validation steps.

## Risks And Tradeoffs

- Local TLS can prove Caddy and approval plumbing without proving public CA
  issuance.
- DuckDNS improves public-fidelity coverage but adds account tokens, DNS
  propagation delays, and external availability risk.
- Device simulation can hide packaging or client defects if it bypasses the Go
  client and FRPC process model.
- Host routing varies across macOS, Linux, Docker, Podman, and Apple Container.
- Tunnel providers such as ngrok are useful for reachability demos but can mask
  Caddy-owned TLS behavior if TLS terminates before Caddy.

## Dependencies

- `deploy/compose/docker-compose.yml`
- `deploy/compose/dev.env`
- `deploy/compose/.env.example`
- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/caddy/Caddyfile.laptop`
- `deploy/compose/frps/frps.toml`
- `.mise/tasks/deploy/dev.sh`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `deploy/compose/scripts/validate_stack.sh`
- `packages/client/Dockerfile`
- `packages/server/Dockerfile`
- `packages/server/lib/nixstasis_web/controllers/tls_controller.ex`
- `packages/server/lib/nixstasis/tls_observations.ex`
- `packages/server/lib/nixstasis/deployment.ex`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex`
- `packages/server/lib/nixstasis/devices/ssh_client.ex`
- `packages/client/internal/frp/manager.go`
- `packages/client/internal/config/config.go`
- `packages/client/cmd/nixstasis/register.go`
- `packages/client/cmd/nixstasis/poll.go`

## Likely Affected Docs

- `docs/src/planned-features.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/modules/server-web.md`
- `deploy/compose/README.md`
- `packages/client/README.md`
- `packages/server/README.md`

## Validation

- Static validation for generated Compose development overrides.
- Local smoke test confirming Caddy reaches Phoenix TLS approval.
- Local smoke test confirming Caddy serves local certificates through default
  laptop hostnames.
- Local smoke test confirming FRPC connects to FRPS using development config.
- ExUnit LiveView integration test that launches a terminal and runs a harmless
  command through a fake SSH client.
- Dev-lab one-command flow starting real client simulators and confirming server
  UI accessibility.
- Optional DuckDNS or real-domain validation that documents certificate issuance,
  DNS challenge behavior, and expected failure modes.
