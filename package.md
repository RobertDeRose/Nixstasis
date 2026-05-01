# Packaging and Deployment Migration Plan

## Goal

Replace server-side Debian package deployment with a container-based deployment strategy built around Docker Compose,
while keeping the device client as a native host-installed package distributed with GoReleaser.

This migration also incorporates the final product rename to `Nixstasis`.

This plan intentionally defers Kubernetes to a future change.

## Decisions

- `packages/client` remains native-distributed.
- `packages/client` migrates to GoReleaser.
- `packages/client` will bundle a pinned `frpc` binary.
- The bundled `frpc` will be installed to a private path: `/usr/libexec/nixstasis/frpc`.
- `packages/server`, `packages/caddy`, and `packages/frp` will no longer target Debian package delivery.
- Server-side deployment target for this change is Docker Compose only.
- Caddy remains a hard requirement because it provides:
  - on-demand TLS
  - OIDC authentication via AuthCrunch
- PostgreSQL will be included in the Compose stack by default.
- PostgreSQL configuration should still allow later use of an external database without changing application code.
- `frps` should track a pinned upstream version using the safest available option:
- preferred: mirrored internal image pinned by digest
- fallback: pinned upstream image by digest

## Product Rename

The packaging and deployment migration should be used as the point where the externally visible product name becomes
`Nixstasis`.

The rename should be treated as part of the same workstream so package names, binary names, service names, config paths,
container names, image names, and documentation all converge on the new name together.

### Naming Intent

- Product name: `Nixstasis`
- Old placeholder name to phase out entirely from the repository
- Future packaging, runtime, and deployment assets should prefer `nixstasis` for filesystem paths and identifiers.

### Planned Naming Conventions

- binary name: `nixstasis`
- bundled private runtime path: `/usr/libexec/nixstasis/`
- config directory: `/etc/nixstasis/`
- persistent/runtime-owned data should move under a `nixstasis` namespace where practical
- service/container/image names should use `nixstasis`

### Migration Rule

Do not preserve any old placeholder naming in newly created packaging or deployment assets unless there is a specific
compatibility requirement. Any compatibility shims, if needed later, should be explicit and temporary.

## End State

### Client

- Built and released with GoReleaser.
- Produces Linux archives, `.deb`, and `.rpm` artifacts.
- Installs:
  - `nixstasis` as a user-facing command
  - `frpc` under `/usr/libexec/nixstasis/frpc`
  - config templates and systemd units
- Does not depend on a separately installed `frp` package.

### Server Deployment

- Deployed with Docker Compose.
- Compose stack includes:
  - `postgres`
  - `nixstasis`
  - `frps`
  - `caddy`
- Caddy is the required public ingress and authentication layer.
- Phoenix is run as a release, not via Mix in production.
- Migrations are run explicitly, not implicitly on app startup.

## Scope

### In Scope

- Add a Docker Compose deployment layout and supporting configuration files.
- Add OCI image build support for server-side components.
- Migrate client packaging to GoReleaser.
- Bundle `frpc` into client artifacts.
- Update CI/CD direction to support container delivery for server-side components and GoReleaser for the client.

### Out of Scope

- Kubernetes manifests or Helm charts.
- Nix flake support for the client.
- Full cleanup of every legacy packaging artifact in the same change, unless necessary to avoid confusion.

## Major Risks to Address First

Before implementation, normalize these mismatches so the new deployment path has a clear runtime contract:

1. Canonical internal app port behind Caddy.
   - Current repo evidence suggests `4000` in Phoenix runtime and `8000` in some Caddy assumptions.

2. Canonical on-demand TLS approval endpoint.
   - Current repo/PoC history references both `/permit_tls` and `/api/v1/check_domain`.

3. Canonical domain naming rules.
   - Current configs and controller logic need one source of truth.

4. Canonical env var names and secret ownership.
   - Caddy/AuthCrunch secrets, Phoenix secrets, and DB credentials must be clearly separated.

5. `frps` version ownership and image source.

## Required Runtime Contract

Define and document these values before wiring Compose:

- `NIXSTASIS_PORT` or fixed internal app port
- `DATABASE_URL` or DB host/user/password/database split
- `SECRET_KEY_BASE`
- `PHX_HOST`
- Caddy/AuthCrunch env vars:
  - `CLIENT_ID`
  - `CLIENT_SECRET`
  - `TENANT_ID`
  - `JWT_KEY`
- `frps` ports:
  - bind/control port
  - HTTP tunnel port
  - dashboard port
  - SSH/tcpmux port
- canonical allowed domain patterns
- canonical TLS approval endpoint path

## Deliverables

### 1. Compose Deployment Layout

Add a new deployment source of truth under `deploy/compose/`.

Planned files:

- `deploy/compose/docker-compose.yml`
- `deploy/compose/.env.example`
- `deploy/compose/README.md`
- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/frps/frps.toml`
- optional helper files:
  - `deploy/compose/env/`
  - `deploy/compose/scripts/`

Compose responsibilities:

- `postgres`
  - default included service
  - named volume for persistence
  - env-driven credentials

- `nixstasis`
  - Phoenix release container
  - depends on DB availability
  - receives runtime env
  - internal only, fronted by Caddy

- `frps`
  - pinned image reference
  - mounted `frps.toml`
  - explicit published ports as required

- `caddy`
  - custom AuthCrunch-enabled image
  - mounted `Caddyfile`
  - published public HTTP/HTTPS ports
  - public edge for auth and TLS

### 2. Server Containerization

Add container build support for `packages/server`.

Planned files:

- `packages/server/Dockerfile`
- optional supporting files:
  - `packages/server/.dockerignore`
  - `packages/server/bin/docker-entrypoint.sh` if needed

Implementation expectations:

- multi-stage build
- build Phoenix assets
- build Phoenix release
- runtime image starts the release via the renamed release command
- provide a documented explicit migration command via `bin/migrate`

Server image responsibilities:

- carry release artifacts only
- not carry systemd or Debian package semantics
- not assume host paths like `/etc/caddy` or `/etc/frp`

### 3. Caddy Containerization

Add OCI image build support for `packages/caddy`.

Planned files:

- `packages/caddy/Dockerfile`
- optional refactor of existing build helper scripts if they remain useful

Implementation expectations:

- use `xcaddy`
- include AuthCrunch plugin
- runtime image should be minimal
- secrets/config should be injected at runtime, not baked into the image

### 4. FRPS Delivery Model

Do not continue server-side Debian packaging for `frps`.

Expected implementation:

- configure Compose to use a pinned image reference for `frps`
- prefer mirrored internal image pinned by digest
- keep repo-managed `frps.toml` under deployment config

Repo responsibilities:

- preserve `frps.toml` as tracked config
- document the exact image pinning policy

### 5. Client GoReleaser Migration

Migrate `packages/client` from the current package workflow to GoReleaser.

Planned files:

- `packages/client/.goreleaser.yaml`
- optional helper scripts:
  - `packages/client/scripts/release/`
  - `packages/client/scripts/fetch_frpc.sh`

Implementation expectations:

- build `nixstasis` for supported Linux targets
- produce archives
- produce `.deb`
- produce `.rpm`
- bundle `frpc` for each target architecture
- install bundled `frpc` under `/usr/libexec/nixstasis/frpc`

Client packaging responsibilities:

- install:
  - `nixstasis`
  - bundled `frpc`
  - config templates
  - systemd units
- remove dependency on a separately installed `frp` package
- keep client host integration intact

### 6. Client Runtime Changes

Update client runtime code to launch bundled `frpc` from a private path.

Expected code changes:

- replace `frpc` PATH lookup assumptions with an explicit configured/bundled path
- define one canonical default path for packaged installs:
  - `/usr/libexec/nixstasis/frpc`
- allow override only if there is a clear config requirement

- update default config paths and any service/runtime path assumptions from `nixstasis` to `nixstasis`

Related areas likely to change:

- `packages/client/internal/frp/manager.go`
- `packages/client/cmd/nixstasis/poll.go`
- client config defaults and docs
- command and path definitions that currently embed `nixstasis`

### 7. CI/CD Changes

#### Server-Side

Add OCI image workflows for:

- `packages/server`
- `packages/caddy`

Potential workflow files:

- `.github/workflows/build_server_image.yml`
- `.github/workflows/build_caddy_image.yml`
- or a single shared image workflow with matrix-based inputs

Expected behavior:

- build image
- tag image deterministically
- push to registry
- optionally publish semver tags on release

#### Client Release Workflow

Add a GoReleaser workflow for `packages/client`.

Potential workflow file:

- `.github/workflows/release_client.yml`

Expected behavior:

- run tests/lint as needed
- fetch pinned `frpc` artifacts per target
- run GoReleaser
- publish client release assets

#### Legacy Workflow Treatment

The following should be treated as migration leftovers and eventually removed or restricted to client-only use:

- `.github/workflows/build_package.yml`
- `.github/workflows/publish_package.yml`
- package-based server/caddy/frp release logic

## Concrete Implementation Sequence

### Phase 1. Normalize Runtime Contract

1. Choose one internal app port.
2. Choose one TLS approval endpoint.
3. Choose one set of domain rules.
4. Document required env vars and secrets.
5. Decide image source and pinning policy for `frps`.

Output of this phase:

- updated docs and config templates that represent the chosen runtime contract

### Phase 2. Add Compose Deployment

1. Create `deploy/compose/docker-compose.yml`.
2. Create `deploy/compose/.env.example`.
3. Add compose-specific `Caddyfile`.
4. Add compose-specific `frps.toml`.
5. Add deployment README with first-run instructions.
6. Use `nixstasis` naming consistently in service names, image tags, and docs.

Output of this phase:

- one documented single-host deployment flow

### Phase 3. Add Server Image Build

1. Add `packages/server/Dockerfile`.
2. Build Phoenix assets and release in image build.
3. Rename release/runtime-facing identifiers from `nixstasis` to `nixstasis`.
4. Validate startup via the renamed release command.
5. Validate migrations via explicit `bin/migrate` command.

Output of this phase:

- runnable `nixstasis` image used by Compose

### Phase 4. Add Caddy Image Build

1. Add `packages/caddy/Dockerfile`.
2. Build Caddy with AuthCrunch.
3. Validate runtime config injection.
4. Validate auth flow and on-demand TLS configuration path.

Output of this phase:

- runnable `caddy` image used by Compose

### Phase 5. Wire FRPS into Compose

1. Pin the chosen `frps` image.
2. Mount `frps.toml`.
3. Validate the required tunnel/dashboard ports.
4. Validate connectivity from Caddy and client assumptions.

Output of this phase:

- runnable `frps` service in Compose

### Phase 6. Migrate Client to GoReleaser

1. Add `.goreleaser.yaml`.
2. Add `frpc` fetch/bundle step.
3. Rename package-owned paths and user-facing command names from `nixstasis` to `nixstasis`.
4. Update package layout to install bundled `frpc` in `libexec`.
5. Update client runtime to invoke bundled path.
6. Generate `.deb` and `.rpm` artifacts.

Output of this phase:

- client-native release pipeline independent of the old package action

### Phase 7. Retire Old Server-Side Packaging Model

1. Update docs to make Compose the primary deployment path.
2. Stop documenting server/caddy/frp Debian packaging as supported deployment output.
3. Restrict or remove old package workflows for non-client packages.

Output of this phase:

- clear separation between client native packaging and server-side container deployment

## Files to Treat as Legacy During Migration

These should not be used as the future source of truth for server-side deployment:

- `packages/server/package_options.yml`
- `packages/server/build/root-dir/**`
- `packages/server/build/pre_package.sh`
- server-side `DEBIAN/*`
- server-side systemd service templates
- server-side package-based wiring for Caddy and FRP
- `packages/caddy/package_options.yml`
- `packages/frp/package_options.yml`

They may remain temporarily during transition, but the new source of truth should become:

- `deploy/compose/**`
- container Dockerfiles
- image build workflows
- client GoReleaser config

## Documentation Updates Required

Update these areas as implementation lands:

- root `README.md`
- `packages/client/README.md`
- `packages/server/README.md`
- any packaging/deployment references that still describe server-side Debian delivery as current
- any docs that still describe the product as `Nixstasis`
- release, package, service, and command documentation that still uses `nixstasis` paths or identifiers

## Validation Checklist

The migration is not complete until all of the following are true:

- `docker compose up` brings up:
  - `postgres`
  - `nixstasis`
  - `frps`
  - `caddy`
- Phoenix is reachable only through Caddy in the intended deployment path.
- Caddy is using the configured AuthCrunch/OIDC flow.
- Caddy can reach the chosen TLS approval endpoint.
- `frps` is reachable on the required ports.
- client packages install bundled `frpc` in `/usr/libexec/nixstasis/frpc`.
- client runtime launches bundled `frpc` successfully.
- client release artifacts are produced by GoReleaser as `.deb` and `.rpm`.
- server-side release docs no longer point users toward Debian package deployment.
- user-facing package, command, service, and path names reflect `Nixstasis` rather than `Nixstasis`.

## Recommended First Implementation Change

The first code change should be to normalize the runtime contract and add `deploy/compose/` as the new deployment
source of truth. That creates a stable base for the server image, Caddy image, and later client packaging migration.
