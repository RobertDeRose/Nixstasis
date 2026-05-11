# Development Laptop Remote Access

## Feature Name

`dev-laptop-remote-access`

## Goal

Provide a repeatable development-laptop workflow that can validate the Nixstasis
remote-access stack without a public domain by default. The workflow must run the
server-side stack, exercise Caddy dynamic TLS approval with local certificates,
register or simulate a managed device, connect FRPC to FRPS, and launch an SSH
terminal from the Phoenix UI through the FRP path.

Optional public-fidelity validation may use DuckDNS or a real operator-owned
domain to test DNS-based ACME behavior, but that path must not be required for
normal development.

## Source Of Intent

- `docs/src/planned-features.md`, feature `dev-laptop-remote-access`
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
- Provide a managed test-device path that registers with the server, runs or
  simulates FRPC, and exposes SSH through FRP so the UI terminal can connect.
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

### Default Laptop Mode

Default laptop mode should be local-first and deterministic:

- Use a development Compose override file for local-only settings.
- Run Phoenix, Caddy, FRPS, and PostgreSQL using the existing Compose shape plus
  development overrides.
- Use Caddy local certificates or internal CA for HTTPS.
- Use local host routing for reserved app hosts and device wildcard hosts.
- Configure Caddy on-demand TLS with the existing Phoenix ask endpoint so domain
  approval remains part of the flow.
- Run a test device using the Go client where practical, with explicit constraints
  for any simulation-only fallback.
- Run an SSH test target reachable only through FRP.

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

The primary managed-device path should run the Go client locally so registration,
polling, and FRPC process management stay close to production behavior. A
containerized client may be added as a secondary convenience path if it uses the
same registration and FRPC boundaries. Simulation-only fallbacks are acceptable
only when documented as lower fidelity and must not be the default terminal
validation path.

### Terminal Smoke Coverage

The minimum terminal smoke test must launch the terminal from `/devices/:id`, run a
harmless command such as `whoami` or `printf nixstasis-smoke`, close the session,
and reopen a terminal for the same test device. This proves command execution and
basic session lifecycle behavior without expanding the feature into exhaustive
terminal resilience testing.

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
- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/frps/frps.toml`
- `packages/server/lib/nixstasis_web/controllers/tls_controller.ex`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex`
- `packages/server/lib/nixstasis/devices/ssh_client.ex`
- `packages/client/internal/frp/manager.go`
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
- Browser/UI or E2E journey that launches a terminal and runs a harmless command
  through SSH.
- Optional DuckDNS or real-domain validation that documents certificate issuance,
  DNS challenge behavior, and expected failure modes.
