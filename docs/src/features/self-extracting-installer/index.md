# Self-Extracting Installer

## Delivery Summary

- Beads feature root: `nixstasis-3ny`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `27175a0c26c34cec44815989f5fac491a66dc99a`
- Design record: `design.md`

## Delivered Capability

Client releases include architecture-specific `.run` installers for systemd Linux hosts without native deb or rpm
package support. Each archive carries the Go client, matching `frpc`, configuration templates, systemd units, installer
entry point, and a checksummed artifact manifest.

## User-Facing Behavior

Operators run the downloaded archive with `sh`, receive FHS-compatible installation, and retain an existing
`/etc/nixstasis/config.yaml` unless replacement is explicitly requested. The archive can be extracted without execution
for inspection.

## Design Integration

The installer reuses GoReleaser output and the shared FRP acquisition path. It supplements rather than replaces deb,
rpm, and tar artifacts, and preserves the existing systemd runtime layout.

## Operational Impact

Upgrades replace client-owned binaries, templates, and units while preserving operator configuration. Installation does
not automatically enable services or provide an uninstall workflow.

## Reference and Contracts

- `packages/client/README.md`
- [`packages/client/build/bin/verify_artifacts.sh`](../../../../packages/client/build/bin/verify_artifacts.sh)
- [`packages/client/build/makeself/entrypoint.sh`](../../../../packages/client/build/makeself/entrypoint.sh)

## Validation Evidence

`packages/client/build/bin/verify_artifacts.sh` extracts `.run` files without execution and validates required payloads,
file modes, and manifest integrity. Legacy release evidence covers amd64 and arm64 assembly and installer verification.

## Design Reconciliation

### Delivered as Designed

The release pipeline produces self-extracting installers with bundled FRP, systemd assets, safe configuration seeding,
and verifiable manifests.

### Intentional Changes

Release tooling was consolidated under mise while retaining GoReleaser as artifact authority.

### Deferred Work

Signing and uninstall support remain future work.

### Rejected or Removed Scope

The feature does not replace native packages, start services automatically, or target macOS and Windows.

## Documentation Updated

- `packages/client/README.md`
- `docs/src/planned-features.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-3ny`. Commit `27175a0c26c34cec44815989f5fac491a66dc99a`
directly updated the artifact verifier while migrating release tooling to mise.
