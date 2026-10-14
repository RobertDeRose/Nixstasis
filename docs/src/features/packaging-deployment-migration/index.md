# Packaging and Deployment Migration

## References

- Beads feature root: `nixstasis-nmm`
- Design record: [design.md](design.md)

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

## Test Coverage

- `deploy/compose/scripts/validate_stack.sh` (tested by `deploy/compose/scripts/test_validate_stack.py`): Compose
  rendering, required server settings, and port exposure.
- `deploy/compose/scripts/check_frps_config.sh` and `deploy/compose/scripts/check_proxy_claims.py`: FRPS and proxy
  configuration checks.
- `packages/server/test/nixstasis_web/runtime_contract_test.exs`: server runtime-contract inputs.
- `packages/client/build/bin/verify_artifacts.sh`: client binaries, bundled FRPC, templates, systemd units, versions,
  and installers.

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
