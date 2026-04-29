# Research: Nixstasis Packaging and Deployment Migration

**Date**: 2026-04-29
**Spec**: `specs/013-nixstasis-packaging-migration/spec.md`

## Decisions

### 1) Supported server deployment model
- **Decision**: Make Docker Compose the single supported server deployment path and treat existing Debian-based server packaging assets as legacy migration leftovers only.
- **Rationale**: The repo currently has multiple package-based server deployment surfaces, but the feature requires one operator-facing source of truth and a simpler runtime contract.
- **Alternatives considered**: Continue dual support for package and Compose deployment; defer the cutover until after container support lands.

### 2) Canonical internal app port
- **Decision**: Standardize the internal Phoenix listener port behind Caddy to `4000`.
- **Rationale**: `packages/server/config/runtime.exs` already defaults Phoenix to `4000`, making it the least disruptive internal contract to preserve.
- **Alternatives considered**: Move Phoenix to `8000`; allow both ports during transition.

### 3) Canonical TLS approval endpoint
- **Decision**: Standardize the on-demand TLS approval path as `GET /api/v1/check_domain`.
- **Rationale**: The current Phoenix router/controller already expose this route, while legacy references to `/permit_tls` are older deployment assumptions that should be retired.
- **Alternatives considered**: Restore `/permit_tls`; support both paths during migration.

### 4) Canonical hostname contract
- **Decision**: Define a single `BASE_DOMAIN` contract with reserved hosts `nixstasis.<base-domain>`, `auth.<base-domain>`, and `frp-admin.<base-domain>`, plus device-specific remote-access hosts `atom-<normalized-device-id>.<base-domain>`.
- **Rationale**: Current repo assets disagree on domain suffixes and reserved names. A single base-domain contract preserves current device-subdomain behavior while aligning the renamed product host.
- **Alternatives considered**: Hardcode one repo-specific domain; rename all device subdomains away from `atom-*` in the same feature.

### 5) Server runtime variable contract
- **Decision**: Use `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, `CLIENT_ID`, `CLIENT_SECRET`, `TENANT_ID`, `JWT_KEY`, `BASE_DOMAIN`, `FRPS_BIND_PORT`, `FRPS_HTTP_PORT`, `FRPS_DASHBOARD_PORT`, and `FRPS_TCPMUX_PORT` as the canonical operator-supplied runtime contract.
- **Rationale**: These values cover current Phoenix runtime inputs, Caddy/AuthCrunch requirements, and the FRPS ports that operators must expose and document.
- **Alternatives considered**: Split database values into host/user/password/database fields only; keep partially implicit FRPS settings in config files.

### 6) Database support model
- **Decision**: Support both a default bundled PostgreSQL service and an externally managed PostgreSQL service in the same feature.
- **Rationale**: The spec requires both operational modes, and Compose can satisfy them cleanly by making the bundled database the default while keeping application configuration centered on `DATABASE_URL`.
- **Alternatives considered**: Support bundled database only; defer external database support until after the first Compose release.

### 7) External artifact pinning policy
- **Decision**: Require pinned, reproducible sourcing for all externally sourced runtime artifacts in scope, using mirrored internal images or binaries when available and upstream digest/checksum pinning otherwise.
- **Rationale**: This feature replaces deployment infrastructure and packaging workflows; reproducibility is necessary to avoid environment drift and release ambiguity.
- **Alternatives considered**: Pin only `frps`; allow client-bundled `frpc` or base images to float.

### 8) Server image behavior
- **Decision**: Build the Phoenix server as a multi-stage OCI image that contains only release artifacts, runs the application as a release, and exposes a separate explicit migration command.
- **Rationale**: The repo already uses Phoenix production conventions and the feature explicitly requires separation between migrations and application startup.
- **Alternatives considered**: Continue Mix-driven production startup; run migrations automatically on app boot.

### 9) Caddy image behavior
- **Decision**: Build Caddy as its own OCI image with AuthCrunch included, inject secrets and config at runtime, and keep the runtime image minimal.
- **Rationale**: Existing package scripts already build custom Caddy, but container delivery requires the customization to move into an image contract instead of a Debian package.
- **Alternatives considered**: Use stock upstream Caddy; bake deployment secrets into the image.

### 10) Client packaging model
- **Decision**: Move `packages/client` to GoReleaser, ship archive, `.deb`, and `.rpm` outputs, install the user-facing binary as `nixstasis`, and bundle `frpc` into the package payload at `/usr/libexec/nixstasis/frpc`.
- **Rationale**: The client must remain host-native while dropping the hard dependency on a separately installed `frp` package.
- **Alternatives considered**: Keep legacy package scripts; continue resolving `frpc` from `PATH`.

### 11) Client runtime path defaults
- **Decision**: Update client defaults to use `/etc/nixstasis/` for configuration and `/usr/libexec/nixstasis/` for bundled runtime helpers, with bundled `frpc` used by default.
- **Rationale**: Current client code hardcodes `/etc/nixstasis` and `/usr/libexec/nixstasis`; the rename requires one canonical path contract.
- **Alternatives considered**: Preserve old paths for compatibility; require operators to configure the bundled helper path manually.

### 12) Workflow split
- **Decision**: Add dedicated image workflows for `packages/server` and `packages/caddy`, add a GoReleaser-based client workflow, and demote existing package workflows to legacy or client-only use.
- **Rationale**: Current CI/CD is package-oriented and does not express the desired server/container delivery model.
- **Alternatives considered**: Reuse current package workflows for image publication; keep one mixed workflow for all deliverables.
