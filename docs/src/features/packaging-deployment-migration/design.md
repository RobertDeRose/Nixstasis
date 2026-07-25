<!-- workflow-migration:legacy-markdown-to-beads -->

# Packaging And Deployment Migration

## Feature Name

`packaging-deployment-migration`

## Goal

Establish one supported deployment path for the server stack and one supported
native packaging/release path for the client while standardizing Nixstasis naming
and runtime contracts.

## Users

- Platform operators deploying the server stack.
- Device administrators installing the client.
- Maintainers producing release artifacts.

## Requirements

- Provide one supported server deployment source of truth under `deploy/compose`.
- Include the required public ingress/authentication layer in the supported stack.
- Support bundled PostgreSQL and externally managed database modes.
- Keep client artifacts host-installable for supported Linux targets.
- Bundle the FRPC helper with client release artifacts in a product-owned path.
- Install user-facing client command, configuration templates, and service assets together.
- Apply Nixstasis naming consistently across release-facing assets.
- Separate application startup from database migration execution.
- Pin externally sourced runtime artifacts reproducibly.
- Fully document operator-supplied runtime settings for supported deployment.

## Proposed Design

The supported server path is Compose-based and documented through `deploy/compose`.
Client packaging uses GoReleaser outputs and shared FRP acquisition scripts. The
runtime contract defines domains, ports, secrets, database configuration, TLS
approval paths, and artifact version pins.

Operator commands and validation procedures belong in `deploy/compose/README.md`,
the top-level README, and deployment module docs.

## Edge Cases

- Operators attempt legacy server package instructions.
- Client hosts lack separately installed tunnel tooling.
- Operators use externally managed databases.
- Required secrets or domain settings are missing.
- External artifacts resolve differently across environments.

## Validation

- Clean server deployment follows only `deploy/compose` guidance.
- Runtime contract identifies all required operator-supplied settings.
- Client artifacts install command, configs, services, and bundled FRPC.
- Release validation verifies pinned external artifacts and package contents.
