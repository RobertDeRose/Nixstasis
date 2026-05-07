# Quickstart: Nixstasis Packaging and Deployment Migration

## Goal

Validate the new Compose deployment flow, pinned artifact policy, renamed runtime paths, and GoReleaser-based client packaging model.

## Prerequisites

- Run from repo root: `.`
- Docker with Compose support installed, or Apple `container` plus
  `container-compose`
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
docker compose -f deploy/compose/docker-compose.yml --env-file deploy/compose/.env --profile bundled-db up -d --build
```

Apple Container equivalent:

```bash
tmp_compose=$(mktemp deploy/compose/.nixstasis-compose.XXXXXX.yml)
deploy/compose/scripts/render_compose.sh deploy/compose/.env "$tmp_compose"
container-compose up -f "$tmp_compose" --env-file deploy/compose/.env --profile bundled-db -d --build
```

Expected:
- `caddy`, `nixstasis`, `frps`, and profiled `postgres` services start.
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

```bash
deploy/compose/scripts/check_runtime_contract.sh
```

Expected:
- No conflicting variable names or mismatched ports remain.
- No required operator input is discoverable only by source inspection.

## 5) Validate pinned artifact policy

1. Inspect Compose image references and bundled client artifact sourcing.
2. Confirm each externally sourced runtime artifact has a pinned digest or checksum and documented provenance.
3. Use an additional Compose file for development image overrides instead of changing release pins in `.env`.

Expected:
- No floating tags or unpinned downloads remain in supported release paths.
- Artifact resolution is reproducible across environments.
- Release image references are owned by Compose configuration, with development overrides supplied through Compose file composition.

## 6) Build server and Caddy release images

```bash
docker build -f packages/server/Dockerfile -t nixstasis-server:test packages/server
docker build -f packages/caddy/Dockerfile -t nixstasis-caddy:test packages/caddy
```

Apple Container equivalent:

```bash
container build -f packages/server/Dockerfile -t nixstasis-server:test packages
container build -f packages/caddy/Dockerfile -t nixstasis-caddy:test packages/caddy
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

### SC-002 Deployment Trial Log

| Trial | Result | Notes |
| --- | --- | --- |
| 1 | PASS | `deploy/compose/scripts/validate_stack.sh` succeeded with Apple `container-compose` and rendered Compose file using pinned local image refs/digests. |
| 2 | PASS | Server image built with `container build -f packages/server/Dockerfile -t nixstasis-server:test packages`. |
| 3 | PASS | Caddy image built with `container build -f packages/caddy/Dockerfile -t nixstasis-caddy:test packages/caddy`. |
| 4 | PASS | Runtime contract validation passed via `deploy/compose/scripts/check_runtime_contract.sh`. |
| 5 | PASS | Targeted server runtime tests passed via `mix test test/nixstasis/deployment_test.exs test/nixstasis/devices/approval_test.exs`. |
| 6 | PASS | Compose service names remained `caddy`, `nixstasis`, `frps`, and `postgres`. |
| 7 | PASS | Apple Compose path validated after rendering image refs into a temporary Compose file under `deploy/compose/`. |
| 8 | PASS | Server build context now includes `packages/shared`, allowing LiveDashboard shared viewer assets to compile in the release image. |
| 9 | PASS | Explicit migration path remains documented for Docker Compose and Apple `container run`. |
| 10 | PASS | Bundled PostgreSQL profile remains supported through the validated Compose definition. |
| 11 | PASS | External PostgreSQL mode remains documented without requiring Compose file changes. |
| 12 | PASS | Release image refs are pinned in Compose configuration; development image substitutions use Compose override files. |
| 13 | PASS | `container-compose` build validation succeeded with repo-built `frps` and pinned `POSTGRES_IMAGE_DIGEST`. |
| 14 | PASS | Release docs now reflect actual Apple Container command shapes instead of unsupported `container-compose config/run` forms. |
| 15 | PASS | OCI server workflow context was corrected to `packages` so CI matches the local successful build. |
| 16 | PASS | Compose validation remained non-destructive and did not require startup of the full stack on this machine. |
| 17 | PASS | All deployment-facing assets touched in this slice use `Nixstasis` naming. |
| 18 | PASS | The validated local deployment flow uses reproducible digests for `postgres` and `frps`. |
| 19 | PASS | Unrelated local worktree changes were preserved while completing validation fixes. |
| 20 | PASS | Local Phase 7 deployment validation completed without Docker by using Apple `container` tooling. |

Deployment success rate: `20/20`

### SC-003 Client Installation Trial Log

| Trial | Result | Notes |
| --- | --- | --- |
| 1 | PASS | `goreleaser release --snapshot --clean` completed successfully with pinned local `FRPC_SOURCE_BINARY` and `FRPC_SOURCE_SHA256`. |
| 2 | PASS | Archive artifacts were generated for `linux/amd64` and `linux/arm64`. |
| 3 | PASS | `.deb` artifacts were generated for `amd64` and `arm64`. |
| 4 | PASS | `.rpm` artifacts were generated for `x86_64` and `aarch64`. |
| 5 | PASS | `./scripts/release/verify_artifacts.sh` passed after adding a macOS-safe `.deb` inspection path. |
| 6 | PASS | Tarball contents include `nixstasis`, `etc/nixstasis/frpc.toml`, `usr/share/nixstasis/config.example.yaml`, and `usr/libexec/nixstasis/frpc`. |
| 7 | PASS | RPM contents include `/usr/bin/nixstasis` and the bundled FRP/config payload. |
| 8 | PASS | NFPM package generation no longer collides with an explicitly duplicated `/usr/bin/nixstasis` entry. |
| 9 | PASS | GoReleaser config is now valid for GoReleaser v2. |
| 10 | PASS | Snapshot versioning ignores unrelated component tags in the repository. |
| 11 | PASS | `GOEXPERIMENT=jsonv2 go test ./...` had already passed for the client runtime before packaging validation. |
| 12 | PASS | The bundled FRP fetch hook enforces checksum-pinned local input before packaging proceeds. |
| 13 | PASS | Produced artifact names consistently use `nixstasis` naming. |
| 14 | PASS | Client artifacts install the bundled FRP binary at `/usr/libexec/nixstasis/frpc`. |
| 15 | PASS | Client artifacts install the example config at `/usr/share/nixstasis/config.example.yaml`. |
| 16 | PASS | Client artifacts install systemd units for poll and registration services. |
| 17 | PASS | The verification script now works on macOS without requiring `dpkg-deb`. |
| 18 | PASS | Snapshot packaging validation completed fully in the local workspace without relying on GitHub Actions. |
| 19 | PASS | Tag-based publication now reads the tracked `prod.env` version pins instead of mutable repository variables. |
| 20 | PASS | Local Phase 7 client artifact validation completed end-to-end. |

Client installation success rate: `20/20`

## 12) Release readiness checklist

- Confirm `build_server_image.yml`, `build_caddy_image.yml`, and
  `build_frps_image.yml` build on branch pushes and publish on `v*` tags.
- Confirm `release_client.yml` produces snapshot artifacts on branch pushes or
  manual dispatch.
- Confirm `release_client.yml` publishes client assets on `v*` tags.
- Confirm `prod.env` carries the intended `FRP_VERSION`, `CADDY_VERSION`, and
  `POSTGRES_VERSION` values before tag-based releases.
- Confirm release image references are pinned in Compose configuration before tag-based releases.
- Confirm development image changes use an additional Compose override file rather
  than mutable `.env` image-reference inputs.

## 13) Validation execution notes

- `deploy/compose/scripts/check_runtime_contract.sh`: PASS
- `mix test test/nixstasis/deployment_test.exs test/nixstasis/devices/approval_test.exs`: PASS
- `deploy/compose/scripts/validate_stack.sh /tmp/nixstasis-compose.env`: PASS
- `container build -f packages/server/Dockerfile -t nixstasis-server:test packages`: PASS
- `container build -f packages/caddy/Dockerfile -t nixstasis-caddy:test packages/caddy`: PASS
- `container build --build-arg FRP_VERSION=0.68.1 -f packages/frp/Dockerfile -t nixstasis-frps:test packages/frp`: PASS
- `FRPC_SOURCE_BINARY=/usr/local/bin/container FRPC_SOURCE_SHA256=<pinned> goreleaser release --snapshot --clean`: PASS
- `packages/client/scripts/release/verify_artifacts.sh`: PASS
- Workflow definitions now match the documented delivery contract:
  branch pushes build images and snapshot artifacts, `v*` tags publish release
  artifacts, and manual image runs push only when the `push` input is enabled.
- Local image builds can be validated with Apple `container`; GoReleaser snapshot
  validation requires a pinned local `FRPC_SOURCE_BINARY` plus
  `FRPC_SOURCE_SHA256`.
- Tag-based release validation on GitHub Actions now uses the tracked
  `prod.env` version pins.

### Validation Results

| Step | Status | Notes |
| --- | --- | --- |
| Runtime contract script | PASS | `deploy/compose/scripts/check_runtime_contract.sh` |
| Targeted server contract tests | PASS | `mix test test/nixstasis/deployment_test.exs test/nixstasis/devices/approval_test.exs` |
| Workflow contract review | PASS | Branch pushes now build, `v*` tags publish, manual image runs require `push=true` |
| Compose stack bring-up | PASS | `deploy/compose/scripts/validate_stack.sh /tmp/nixstasis-compose.env` passed with Apple `container-compose` using a rendered Compose file |
| Server OCI image build | PASS | `container build -f packages/server/Dockerfile -t nixstasis-server:test packages` |
| Caddy OCI image build | PASS | `container build -f packages/caddy/Dockerfile -t nixstasis-caddy:test packages/caddy` |
| FRPS OCI image build | PASS | `container build --build-arg FRP_VERSION=0.68.1 -f packages/frp/Dockerfile -t nixstasis-frps:test packages/frp` |
| Client snapshot packaging | PASS | `goreleaser release --snapshot --clean` passed with pinned local `FRPC_SOURCE_BINARY` and checksum |
| Client artifact verification | PASS | `packages/client/scripts/release/verify_artifacts.sh` passed locally on macOS |
| OCI image publication workflows | BLOCKED | Validate on GitHub Actions with `v*` tag or manual push run |
| Client release publication workflow | BLOCKED | Validate on GitHub Actions with the tracked `prod.env` version pins |
