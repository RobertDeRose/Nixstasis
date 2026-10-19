# Production Operations Runbooks

Operators have a set of runbooks for the supported Compose deployment: backup and restore, secret rotation, health
checks, incidents, upgrades and rollbacks, and a clear statement of what availability and scaling it does and does not
offer. The original plan is in the [design record](design.md).

## What changed for users

The Operations section gives step-by-step maintenance and recovery procedures for the bundled or an external
PostgreSQL, Caddy and AuthCrunch, FRPS, Phoenix, device credentials, and release artifacts.

## How it fits in

The runbooks point at the tracked Compose configuration and validation scripts rather than repeating them, so there is
only one source for how the deployment is set up. Production procedures are kept apart from the local development lab.

## Running it

Each procedure says which services to restart, how to check the result, what failure looks like, and how far a
rollback can go, without promising high availability the deployment does not have. Examples use made-up credentials
and hostnames.

## Differences from the design

A Command Policies page was added alongside the runbooks that were planned.

## Not included

- There is no automatic failover and no hosted operations service.
- The runbooks don't replace your own backup platform, and don't imply any clustering.

## Tests

- `mise run docs:build` builds the operations pages and their navigation.
- `deploy/compose/scripts/validate_stack.sh`, tested by `deploy/compose/scripts/test_validate_stack.py`, checks the
  Compose settings the runbooks rely on.
- `deploy/compose/scripts/check_proxy_claims.py` and `deploy/compose/scripts/check_frps_config.sh` check the proxy claim
  and FRPS configuration the runbooks describe.
- The procedures were checked by hand against the tracked Compose files and validation scripts.

## Related pages

- [Operations](../../operations/index.md)
- [Backup And Restore](../../operations/backup-restore.md)
- [Secret Rotation](../../operations/secret-rotation.md)
- [Health Checks](../../operations/health-checks.md)
- [Incident Response](../../operations/incidents.md)
- [Upgrades And Rollbacks](../../operations/upgrades-rollbacks.md)
- [HA And Scaling](../../operations/ha-scaling.md)
