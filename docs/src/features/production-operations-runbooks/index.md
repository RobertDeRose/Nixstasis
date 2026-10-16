# Production Operations Runbooks

## References

- Beads feature root: `nixstasis-41x`
- Design record: [design.md](design.md)

## Delivered Capability

Production operators have a dedicated runbook set for backup and restore, secret rotation, health checks, incidents,
upgrades and rollbacks, and explicit availability and scaling boundaries for the supported Compose deployment.

## User-Facing Behavior

The Operations section provides task-oriented recovery and maintenance procedures for bundled and external PostgreSQL,
Caddy/AuthCrunch, FRPS, Phoenix, device credentials, and release artifacts.

## Design Integration

Runbooks link to tracked Compose configuration and validation scripts instead of becoming a second deployment authority.
Production procedures remain separate from local development harness guidance.

## Operational Impact

Operators can identify restart scope, validation steps, failure symptoms, and rollback boundaries without unsupported HA
claims. Examples avoid real credentials and production hostnames.

## Reference and Contracts

- [Production Operations](../../operations/index.md)
- [Backup and Restore](../../operations/backup-restore.md)
- [Secret Rotation](../../operations/secret-rotation.md)
- [Upgrades and Rollbacks](../../operations/upgrades-rollbacks.md)

## Test Coverage

- `mdbook build docs` builds the operations pages and their navigation.
- `deploy/compose/scripts/validate_stack.sh` (tested by `deploy/compose/scripts/test_validate_stack.py`) validates the
  Compose runtime contract that the runbooks reference.
- `deploy/compose/scripts/check_proxy_claims.py` and `deploy/compose/scripts/check_frps_config.sh` guard the proxy claim
  and FRPS configuration inputs that the runbooks describe.
- Runbook procedures are manually checked against the tracked Compose inputs and runtime validation scripts.

## Design Reconciliation

### Delivered as Designed

All proposed operator workflow areas were delivered as separately navigable runbook pages.

### Intentional Changes

The final structure includes a dedicated command-policy operations page alongside the originally planned runbooks.

### Deferred Work

Automated failover and hosted operations remain outside the supported deployment.

### Rejected or Removed Scope

The runbooks do not replace operator-specific backup platforms or imply clustered semantics.

## Documentation Updated

- `docs/src/operations/index.md`
- `docs/src/operations/backup-restore.md`
- `docs/src/operations/secret-rotation.md`
- `docs/src/operations/health-checks.md`
- `docs/src/operations/incidents.md`
- `docs/src/operations/upgrades-rollbacks.md`
- `docs/src/operations/ha-scaling.md`
