# Quickstart: Nixstasis Packaging and Deployment Migration

## Goal

Validate the new Compose deployment flow, pinned artifact policy, renamed runtime paths, and GoReleaser-based client packaging model.

## Prerequisites

- Run from repo root: `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis`
- Docker with Compose support installed
- Elixir and Erlang installed for `packages/server`
- Go and GoReleaser installed for `packages/client`
- Required runtime secrets and domain values prepared for `deploy/compose/.env`

## 1) Verify documentation and contract assets exist

Confirm these files are present and internally consistent:

- `deploy/compose/docker-compose.yml`
- `deploy/compose/.env.example`
- `deploy/compose/README.md`
- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/frps/frps.toml`
- `packages/server/Dockerfile`
- `packages/caddy/Dockerfile`
- `packages/client/.goreleaser.yaml`

Expected:
- All deployment and release assets use `nixstasis` naming.
- The runtime contract matches `specs/013-nixstasis-packaging-migration/contracts/compose-runtime-contract.md`.

## 2) Build and start the supported Compose stack

```bash
docker compose -f deploy/compose/docker-compose.yml --env-file deploy/compose/.env up -d --build
```

Expected:
- `caddy`, `nixstasis`, `frps`, and default `postgres` services start.
- Phoenix is not directly exposed as a supported public service.
- Caddy is the public ingress/authentication layer.

## 3) Run explicit database migrations

```bash
docker compose -f deploy/compose/docker-compose.yml --env-file deploy/compose/.env run --rm nixstasis bin/migrate
```

Expected:
- Migrations run successfully without requiring normal app startup.
- Re-running the application does not implicitly run migrations.

## 4) Validate runtime contract alignment

1. Compare `deploy/compose/.env.example`, `deploy/compose/caddy/Caddyfile`, `deploy/compose/frps/frps.toml`, and `packages/server/config/runtime.exs`.
2. Confirm the canonical internal Phoenix port is `4000`.
3. Confirm the TLS approval path is `/api/v1/check_domain`.
4. Confirm all required operator-supplied settings are documented from one source.

Expected:
- No conflicting variable names or mismatched ports remain.
- No required operator input is discoverable only by source inspection.

## 5) Validate pinned artifact policy

1. Inspect Compose image references and bundled client artifact sourcing.
2. Confirm each externally sourced runtime artifact has a pinned digest or checksum and documented provenance.

Expected:
- No floating tags or unpinned downloads remain in supported release paths.
- Artifact resolution is reproducible across environments.

## 6) Build server and Caddy release images

```bash
docker build -f packages/server/Dockerfile -t nixstasis-server:test packages/server
docker build -f packages/caddy/Dockerfile -t nixstasis-caddy:test packages/caddy
```

Expected:
- Images build successfully from repo sources.
- Server image contains release artifacts only.
- Caddy image contains AuthCrunch support and expects runtime-injected configuration.

## 7) Run server test suite relevant to runtime contract changes

```bash
cd packages/server
mix test
```

Expected:
- Existing and new server tests pass.
- Tests cover changed runtime-contract behavior, renamed assets where applicable, and BDD expectations for any touched endpoints.

## 8) Build client release artifacts with GoReleaser

```bash
cd packages/client
goreleaser release --snapshot --clean
```

Expected:
- Archive, `.deb`, and `.rpm` artifacts are generated.
- Artifacts install the `nixstasis` command and bundled `frpc` at `/usr/libexec/nixstasis/frpc`.

## 9) Run client test suite relevant to packaged path behavior

```bash
cd packages/client
go test ./...
```

Expected:
- Client tests pass.
- Tests cover default path resolution, bundled `frpc` execution, and renamed config/runtime paths.

## 10) Validate no touched asset retains legacy product naming

Review changed files under `deploy/compose`, `packages/server`, `packages/caddy`, `packages/frp`, `packages/client`, `.github/workflows`, and updated docs.

Expected:
- Touched assets use `Nixstasis` naming consistently.
- No updated deployment or release asset still presents `Nixstasis` as the current name.

## 11) Validation sampling for SC-002 and SC-003

- Record at least 20 server deployment trials for SC-002.
- Record at least 20 client installation trials for SC-003.
- Mark each trial as success or failure with a short reason.
- Compute the success rate as successful trials divided by total trials.
