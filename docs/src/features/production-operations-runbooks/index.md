# Production Operations Runbooks

## Delivery Summary

- Beads feature root: `nixstasis-41x`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `6d9d5ebd4d6887bcafb7029b552718cbf342bf33`
- Design record: `design.md`

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

## Validation Evidence

Documentation reconciliation checked every runbook against Compose inputs and runtime validation scripts, then built the
mdBook. `docs/src/operations/backup-restore.md` and commit `6d9d5ebd4d6887bcafb7029b552718cbf342bf33`
provide direct historical corroboration.

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

## Audit Trail

Legacy tasks were imported beneath `nixstasis-41x`. Commit `6d9d5ebd4d6887bcafb7029b552718cbf342bf33`
reconciled the delivered operations documentation against current behavior.
