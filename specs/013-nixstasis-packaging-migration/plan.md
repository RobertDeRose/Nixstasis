# Implementation Plan: Nixstasis Packaging and Deployment Migration

**Branch**: `013-nixstasis-packaging-migration` | **Date**: 2026-04-29 | **Spec**: `specs/013-nixstasis-packaging-migration/spec.md`
**Input**: Feature specification from `specs/013-nixstasis-packaging-migration/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Replace the repo's server-side Debian packaging flow with a single Docker Compose deployment source of truth, add OCI image build support for the Phoenix server and AuthCrunch-enabled Caddy, keep the Go client as a native package distributed through GoReleaser with a bundled `frpc`, and complete the `Nixstasis` to `Nixstasis` naming cutover across all assets touched by the migration. The plan standardizes the runtime contract, defines pinned artifact policies, and separates delivery into four interfaces: compose deployment, server image build, Caddy image build, and client-native release artifacts.

## Technical Context

**Language/Version**: Elixir 1.19.5 / Erlang OTP 28 for `packages/server`; Go 1.25.4 for `packages/client`; Docker Compose specification for deployment assets
**Primary Dependencies**: Phoenix 1.8 LiveView, Ecto/Postgres, Cobra/Viper, GoReleaser, Docker Compose, Caddy with AuthCrunch, FRP (`frps`/`frpc`)
**Storage**: PostgreSQL for application data; filesystem-based deployment configuration and packaged client assets
**Testing**: ExUnit BDD and LiveView tests in `packages/server/test`, targeted Go unit tests in `packages/client`, Docker Compose smoke validation, release artifact verification, and workflow dry runs where supported
**Target Platform**: Linux server hosts for Compose deployment, Linux client hosts for native package installs, GitHub Actions for CI/CD
**Project Type**: Monorepo web service + client agent + deployment/release infrastructure
**Performance Goals**: Supported deployment boots reproducibly on a clean host, Phoenix remains reachable only behind Caddy, client installation succeeds without a separate FRP package, and pinned artifacts resolve identically across environments
**Constraints**: No Kubernetes deliverables, no server-side Debian delivery as a supported outcome, explicit migration execution separate from app startup, no remaining `Nixstasis` naming in assets touched by this feature, and all external runtime artifacts in scope must be pinned and reproducible
**Scale/Scope**: `deploy/compose/**`, `packages/server/**`, `packages/caddy/**`, `packages/frp/**`, `packages/client/**`, `.github/workflows/**`, and deployment/release documentation at repo root and package level

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Quality & Simplicity: Pass. The plan replaces multiple divergent server deployment paths with one explicit deployment source of truth and keeps client packaging changes within the existing package boundary.
- Behavior-Driven API Testing: Pass. Server runtime-contract and remote-access behavior changes will require Given/When/Then coverage around approval routing, deployment-facing endpoints, and release validation where server behavior changes.
- Targeted Unit Testing: Pass. Client path resolution, bundled `frpc` execution defaults, and any server-side runtime-contract normalization must receive focused unit tests.
- User Experience First: Pass. Operator experience improves through a single documented deployment path and clearer install/runtime expectations for client administrators.
- Branding: Pass. The feature explicitly removes legacy `Nixstasis` naming from all touched assets and documentation in favor of `Nixstasis`.
- Performance Compliance: Pass. Plan preserves current Phoenix runtime defaults, keeps ingress/TLS termination at Caddy, and requires reproducible artifact sourcing to avoid environment drift.

**Post-Design Check (after Phase 1)**: Pass. Research and design artifacts keep the migration bounded to one deployment path, preserve required testing gates, and document explicit operator contracts without introducing constitution violations.

## Project Structure

### Documentation (this feature)

```text
specs/013-nixstasis-packaging-migration/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── compose-runtime-contract.md
│   └── release-artifact-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
deploy/
└── compose/
    ├── docker-compose.yml
    ├── .env.example
    ├── README.md
    ├── caddy/
    │   └── Caddyfile
    └── frps/
        └── frps.toml

packages/
├── server/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── bin/
│   ├── config/
│   ├── lib/
│   ├── priv/
│   └── test/
├── client/
│   ├── .goreleaser.yaml
│   ├── cmd/
│   ├── internal/
│   ├── scripts/
│   └── README.md
├── caddy/
│   ├── Dockerfile
│   ├── bin/
│   └── package_options.yml
└── frp/
    ├── bin/
    └── package_options.yml

.github/
└── workflows/
    ├── build_server_image.yml
    ├── build_caddy_image.yml
    ├── release_client.yml
    ├── build_package.yml
    └── publish_package.yml
```

**Structure Decision**: Keep the feature aligned with the repo's monorepo structure. New deployment assets live under `deploy/compose`, server and Caddy containerization stay with their package directories, client packaging remains inside `packages/client`, and workflow migration happens in `.github/workflows`. Legacy server package assets may remain temporarily, but only as migration leftovers rather than source-of-truth inputs.

## Baseline Decisions

- Canonical internal Phoenix port behind Caddy: `4000`
- Canonical TLS approval endpoint path: `/api/v1/check_domain`
- Canonical public hostname strategy: one `BASE_DOMAIN` with reserved hosts `nixstasis`, `auth`, and `frp-admin`, plus device subdomains `atom-<normalized-device-id>.<base-domain>`
- Canonical server runtime variables: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, `BASE_DOMAIN`, `CLIENT_ID`, `CLIENT_SECRET`, `TENANT_ID`, `JWT_KEY`, and explicit FRPS port variables
- Canonical artifact sourcing policy: mirrored internal image or binary pinned by digest/checksum when available, otherwise upstream digest/checksum pinning with documented provenance

## Implementation Notes

- Rename boundaries must include package names, binary names, service names, config paths, image names, container names, and all deployment/release documentation touched by this feature.
- Rename boundaries also include full server and client code namespace updates where required to complete the Nixstasis cutover.
- Compose is the supported deployment contract; package-based server deployment docs and workflows become legacy and must no longer be presented as the current path.
- Server image design must expose explicit migration execution separate from application startup.
- Client packaging must install a bundled `frpc` to `/usr/libexec/nixstasis/frpc` and default runtime execution to that path.
- Workflow changes should preserve validation quality gates while splitting server/container delivery from client/package delivery.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| None | N/A | N/A |
