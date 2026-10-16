# Planned Features

This page is the human-readable roadmap of planned work. Beads is authoritative for live status, dependencies,
claims, and ready-work selection. Completed features leave this page; their records live under Implemented Features.

## Project Overview

Nixstasis needs a Compose development harness that exercises the same remote-access
boundaries operators rely on in deployment. Local development must be able to test
dynamic TLS approval and browser-driven SSH terminal flows without waiting for a
production-like environment.

Nixstasis also needs a server-managed Stary script lifecycle so operators can
author, validate, test, and deploy telemetry scripts from the web interface
instead of relying only on client-local CLI workflows.

Because Stary scripts can call `exec_cmd`, Nixstasis needs server-managed command
allowlist policies that operators can compose into categories and assign to
specific devices before those scripts are allowed to execute host commands.

Operators also need first-class device groups in the Dashboard Devices view so
they can organize fleets by operational ownership, location, role, or rollout
cohort instead of relying only on product, account, status, and search filters.

The server UI now has bounded catalog reads so large fleets, rule catalogs, report definitions, and command-policy categories do not materialize entire collections in LiveView state or browser diffs. Delivered behavior and evidence are recorded in [Bounded LiveView Catalog Reads](features/bounded-liveview-catalog-reads/index.md).

## Goals

- Provide a repeatable Compose development harness for end-to-end remote-access
  validation.
- Make Caddy on-demand TLS approval testable from local development workflows.
- Make UI-launched SSH terminal sessions testable from local development workflows.
- Keep the development workflow aligned with documented runtime boundaries for
  Phoenix, Caddy, FRPS, FRPC, and managed-device identity.
- Support an optional public-fidelity mode using DuckDNS or a real operator-owned
  domain when developers need to validate public ACME behavior.
- Provide a browser-based workflow for developing Stary scripts, editing
  front-matter metadata, validating syntax and schema declarations, and testing
  candidate scripts against selected managed clients before deployment.
- Provide a browser-based workflow for defining command execution allowlists,
  grouping them into reusable categories, and assigning the resulting policy to
  selected devices.
- Provide a Devices view workflow for creating, editing, filtering by, and
  assigning operator-managed device groups.

## Non-Goals

- Replacing the supported production Compose deployment path.
- Changing production TLS policy or public ingress requirements.
- Building a full hosted staging environment.
- Making local development depend on public DNS or public certificate issuance when
  a local equivalent can validate the same application behavior.
- Requiring ngrok, localtunnel, or another third-party tunnel provider for the
  default development workflow.
- Replacing the client-side Stary runtime, script parser, schema validator, or
  CLI workflows that already support local development.
- Treating server-side script tests as a substitute for client-side runtime
  enforcement during normal polling.
- Turning `exec_cmd` into a general remote shell, arbitrary command runner, or
  package-management framework.
- Allowing scripts to grant themselves additional command execution permissions.
- Treating product name, account number, approval status, or ad hoc search
  filters as a complete replacement for durable operator-managed groups.
- Keep large LiveView collections bounded in SQL and expose search or pagination instead of silently hiding records.
- Treat `/alerts/rules` as the canonical rule-management surface; Nixstasis is unreleased and does not retain duplicate legacy UI implementations.

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
- The server web interface may orchestrate Stary validation and test execution,
  but clients remain the authoritative execution environment for runtime behavior
  and builtin availability.
- Server-managed script deployment must be auditable and scoped to explicit
  client selections, groups, or future targeting rules rather than silently
  changing every managed client.
- Server-managed command allowlists must remain deny-by-default, use explicit
  absolute executable paths, and be resolved into device-local runtime policy
  before a Stary script can execute `exec_cmd`.
- Composed allowlist categories are additive only in the first version; removing
  or narrowing permissions requires changing the assigned category or device
  policy rather than relying on hidden precedence rules.
- Device groups are operator-managed fleet organization records, not a source of
  device identity. Registration and heartbeat authentication continue to depend
  on device identity, approval state, and API tokens.

## Cross-Cutting Decisions

- Treat local dynamic TLS and UI SSH validation as one development-environment
  feature because both depend on the same local ingress, DNS/host routing, FRPS,
  and device-client simulation shape.
- Default development mode uses local-only trust and routing mechanisms instead of
  public DNS or real public certificate issuance.
- DuckDNS or a real domain is an optional validation path for public ACME fidelity,
  not a prerequisite for local feature development.
- Keep production Compose docs and Compose dev-harness docs explicitly separated so
  test affordances do not become accidental production guidance.
- Treat server-side Stary authoring as a new script-management feature layered on
  top of the completed client-local Starlark script system.
- Validate front matter and Starlark syntax before dispatching tests to clients,
  while still requiring selected clients to execute test runs so builtin,
  environment, timeout, and output-schema behavior matches reality.
- Keep server-managed Stary authoring, command allowlist management, and device
  groups as independent feature tracks. They may integrate later, but each should
  be specifiable, implementable, and testable on its own.
- The command policy UI can call entries "whitelists" for operator familiarity,
  but implementation docs use "allowlist" for consistency with the existing
  `exec_cmd` runtime boundary.

## Resolved Questions

- The managed test device runs as a containerized client with systemd, sshd, frpc,
  and the Go client binary — matching real device lifecycle.
- Reserved local hostnames: `nixstasis.localhost`, `auth.localhost`,
  `frp-admin.localhost`, and `atom-<normalized-device-id>.localhost`.
- Terminal smoke test covers session open, command execution, session close, and
  reopen via ExUnit LiveView integration test with a fake SSH client.
- DuckDNS support is documented as optional manual setup guidance; no DNS-provider
  abstraction was added.

## Backlog

- Move bespoke Phoenix controller APIs under Ash-backed actions/resources where
  practical so their OpenAPI contracts can be generated from the same source of
  truth as the `/api/json` surface.

## Feature Map

### OS updates

Operators roll out signed RAUC OS bundles to approved devices from Nixstasis instead of running a separate update
server next to it. The first consumer is AtomixOS. The work covers OS release records per RAUC compatible registered
from CI, bundle hosting outside Phoenix with signed range-capable URLs, RAUC status in client heartbeat telemetry,
staged rollouts to devices and groups, `os_update` command delivery and installation on the client, and an operator
UI for releases and rollouts. Beads tracks it as `nixstasis-f9j`.
