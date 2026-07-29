# Packaging and Deployment Migration

## Delivery Summary

- Beads feature root: `nixstasis-nmm`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `ce8c2aff454a735df9f16dec9795370f41f5a3fb`
- Design record: `design.md`

## Delivered Capability

Nixstasis has one supported Compose server deployment and one GoReleaser-based client release path with bundled FRPC,
configuration templates, systemd assets, reproducible runtime versions, and release validation.

## User-Facing Behavior

Operators deploy Phoenix, Caddy/AuthCrunch, FRPS, and PostgreSQL from `deploy/compose`; device administrators install
native or self-extracting client artifacts without separately provisioning FRPC.

## Design Integration

Compose owns server topology and runtime contracts. GoReleaser and shared FRP acquisition own client artifacts.
Database migration execution remains separate from application startup.

## Operational Impact

Runtime-contract and stack-validation scripts detect missing settings, unsafe port exposure, image drift, and packaging
mismatches before release or deployment.

## Reference and Contracts

- `deploy/compose/README.md`
- [Deployment Compose](../../modules/deployment-compose.md)
- `packages/client/README.md`

## Validation Evidence

Compose rendering and runtime-contract checks validate server inputs and exposure. Client artifact verification checks
binaries, FRPC, templates, units, versions, and installers. `deploy/compose/docker-compose.yml` is direct evidence.

## Design Reconciliation

### Delivered as Designed

The supported deployment and release paths, bundled FRPC, naming, version pins, and documented runtime settings were
delivered.

### Intentional Changes

The final release path added self-extracting installers and consolidated tooling under mise.

### Deferred Work

Unsupported legacy server packaging remains abandoned rather than maintained.

### Rejected or Removed Scope

The migration did not preserve multiple competing server deployment authorities.

## Documentation Updated

- `README.md`
- `deploy/compose/README.md`
- `packages/client/README.md`
- `docs/src/modules/deployment-compose.md`

## Audit Trail

Legacy tasks were imported beneath `nixstasis-nmm`. Commit `ce8c2aff454a735df9f16dec9795370f41f5a3fb`
directly established the Compose deployment foundation used by the delivered path.
