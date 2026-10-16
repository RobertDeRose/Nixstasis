# Self-Extracting Installer

## References

- Beads feature root: `nixstasis-3ny`
- Design record: [design.md](design.md)

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

## Test Coverage

- `packages/client/build/bin/verify_artifacts.sh` with `VERIFY_INSTALLERS=true` extracts `.run` files without
  execution and validates required payloads, file modes, and manifest integrity.
- `.github/workflows/release_client.yml` runs the installer verification before uploading release artifacts.

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
