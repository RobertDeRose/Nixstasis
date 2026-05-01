# Contract: Release Artifacts and Naming

## Purpose

Define the required release outputs, naming rules, and sourcing guarantees for this migration.

## Server-Side Deliverables

| Deliverable | Format | Naming Rule | Required Behavior |
| --- | --- | --- | --- |
| Phoenix application image | OCI image | Uses `nixstasis` naming | Contains release artifacts only and supports explicit migration execution. |
| Caddy image | OCI image | Uses `nixstasis`-aligned deployment naming | Includes AuthCrunch, accepts runtime config/secrets, and remains minimal. |
| FRPS runtime source | Pinned image reference | Documented in deployment config | Must be pinned by digest and treated as an external runtime artifact rather than a Debian package. |

## Client Deliverables

| Deliverable | Format | Naming Rule | Required Behavior |
| --- | --- | --- | --- |
| Client archive | Archive | Uses `nixstasis` binary and path names | Includes bundled `frpc` and configuration templates. |
| Client native package | `.deb` | Uses `nixstasis` package/binary/path names | Installs bundled `frpc` to `/usr/libexec/nixstasis/frpc`. |
| Client native package | `.rpm` | Uses `nixstasis` package/binary/path names | Installs bundled `frpc` to `/usr/libexec/nixstasis/frpc`. |

## Naming Rules

- Assets created or updated within this feature must use `Nixstasis` / `nixstasis` naming.
- No touched asset may continue to present `Nixstasis` as the current product name.
- Naming coverage includes:
  - package names
  - binary names
  - system/service names
  - config paths
  - image names
  - container names
  - deployment documentation

## Artifact Sourcing Rules

- Every externally sourced runtime artifact in scope must use an immutable pin.
- Preferred sourcing order:
  1. Internal mirrored artifact pinned by digest or checksum
  2. Upstream artifact pinned by digest or checksum
- Floating tags or unpinned downloads are not allowed in supported releases for this feature.

## Workflow Rules

- Server and Caddy publication workflows build and publish OCI images.
- Client publication workflow runs GoReleaser and emits archive, `.deb`, and `.rpm` assets.
- Abandoned server package workflows should be removed when they no longer serve the supported release path.
