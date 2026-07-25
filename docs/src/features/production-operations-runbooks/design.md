<!-- workflow-migration:legacy-markdown-to-beads -->

# Production Operations Runbooks Design

## Summary

Add production operations runbooks for the supported Compose deployment. The
runbooks document backup and restore, secret rotation, operational health checks,
incident response, upgrade and rollback validation, and explicit availability
boundaries for Nixstasis production operators.

## Source Of Intent

This feature is planned in `docs/src/planned-features.md` as
`production-operations-runbooks`.

## Goals

- Document PostgreSQL backup and restore workflows for bundled and external
  database modes.
- Document secret rotation procedures for Phoenix secrets, AuthCrunch/OIDC
  values, AuthCrunch authorization role/group inputs, JWT key material, FRPS auth
  and dashboard credentials, and database credentials.
- Document operational health checks for Phoenix, Caddy, FRPS, PostgreSQL,
  device heartbeat freshness, E2E retention, and remote-access availability.
- Document incident-response playbooks for failed migrations, broken TLS
  approval, FRPS token exposure, device credential compromise, and E2E
  retention/log failures.
- Document upgrade and rollback validation steps for Compose services and client
  release artifacts.
- State HA and scaling boundaries clearly for the supported deployment shape.

## Non-Goals

- Build a hosted operations platform.
- Replace operator-specific backup tooling.
- Implement HA, clustering, or automated failover.
- Replace the supported `deploy/compose` deployment path.
- Merge local development harness guidance into production operations docs.

## Constraints

- Do not imply unsupported HA or clustered deployment semantics unless they are
  implemented and tested.
- Keep production runbooks separate from local development harness guidance.
- Preserve `deploy/compose` as the supported server deployment path.
- Prefer links to source scripts and configuration over duplicated command logic
  where drift is likely.
- Keep examples free of real secrets, operator tokens, and production hostnames.
- Treat `.env.example`, `deploy/compose/docker-compose.yml`, and
  `deploy/compose/README.md` as the source of truth for supported production
  Compose inputs.

## Affected Documentation

- `deploy/compose/README.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/SUMMARY.md`
- New operations runbook page or pages under `docs/src/operations/`

## Design

### Documentation Shape

Add production operations documentation as a dedicated Operations runbook section
under `docs/src/operations/` rather than extending local development docs. The
section should be reachable from the mdBook summary and should link back to
`deploy/compose/README.md` for deployment commands and Compose file details.

Candidate structure:

- `docs/src/operations/index.md`: production operations overview and links.
- `docs/src/operations/backup-restore.md`: backup and restore.
- `docs/src/operations/secret-rotation.md`: secret rotation.
- `docs/src/operations/health-checks.md`: health checks.
- `docs/src/operations/incidents.md`: incident response.
- `docs/src/operations/upgrades-rollbacks.md`: upgrade and rollback.
- `docs/src/operations/ha-scaling.md`: HA and scaling expectations.

If implementation reveals that a single page is more maintainable, the runbooks
may be consolidated, but the final mdBook navigation must still expose the same
operator workflows clearly.

### Backup And Restore

Document two database modes:

- Bundled PostgreSQL in the supported Compose stack.
- External PostgreSQL managed by the operator.

The bundled path should identify where Compose state lives, how to take a logical
backup, how to restore into a disposable or recovered stack, and which services
must be stopped or restarted. The external path should define the Nixstasis
application validation steps while deferring storage-specific implementation to
the operator's database platform.

### Secret Rotation

Document rotation impact and restart requirements for:

- Phoenix secret key base and signing material.
- AuthCrunch/OIDC values.
- AuthCrunch `AUTHORIZED_ROLES` and `AUTHORIZED_GROUPS` inputs.
- JWT key material.
- FRPS auth token.
- FRPS dashboard credentials.
- Database credentials.

Each rotation entry should include symptoms of stale configuration, services to
restart, and post-rotation validation.

### Health Checks

Define operator-visible checks for:

- Phoenix HTTP readiness through Caddy.
- Caddy certificate and reverse proxy behavior.
- FRPS control/dashboard availability.
- PostgreSQL connectivity and migration state.
- Device heartbeat freshness.
- E2E retention health.
- Remote access availability from UI request through FRP and terminal startup.
- Runtime contract drift via `deploy/compose/scripts/check_runtime_contract.sh`
  and Compose render validation via `deploy/compose/scripts/validate_stack.sh`.

Where possible, link to existing scripts such as
`deploy/compose/scripts/check_runtime_contract.sh` instead of duplicating
contract assertions.

### Incident Response

Provide short playbooks for:

- Failed migrations.
- Broken TLS approval.
- FRPS token exposure.
- Device credential compromise.
- E2E retention or log failures.

Each playbook should cover likely symptoms, immediate containment, recovery
steps, and validation checks.

### Upgrade And Rollback

Document a conservative upgrade flow for Compose services and client release
artifacts. Include preflight checks, backup expectations, migration validation,
post-upgrade runtime checks, and rollback boundaries. Production image guidance
must preserve digest-pinned GHCR references rather than mutable tags.

### HA And Scaling Boundaries

State explicitly what the Compose deployment does and does not guarantee. The
first runbook version should not imply multi-node Phoenix, clustered FRPS, or HA
PostgreSQL support unless those capabilities are implemented separately.

## Success Criteria

- A production operator can restore service from backup using documented steps.
- A production operator can rotate each documented secret without guessing which
  services must restart.
- The docs identify observable symptoms, immediate mitigations, and validation
  checks for common incidents.
- HA and scaling expectations are explicit rather than implied.
- `mdbook build docs` succeeds and navigation exposes the runbooks clearly.

## Risks And Tradeoffs

- Runbooks can become stale if they duplicate scripts or Compose configuration
  instead of linking to source-controlled validation.
- Over-prescriptive backup tooling can conflict with an operator's managed
  database platform.
- A single large runbook page can become hard to scan; too many pages can make the
  first implementation harder to maintain.

## Dependencies

- `deploy/compose/docker-compose.yml`
- `deploy/compose/.env.example`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `deploy/compose/scripts/validate_stack.sh`
- `deploy/compose/README.md`
- `docs/src/SUMMARY.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/runtime-boundaries.md`

## Validation

- Build the docs with `mdbook build docs`.
- Validate links and navigation for the new operations content.
- Where practical, exercise backup/restore against a disposable Compose stack.
- Run runtime contract checks before and after documented secret rotation steps.
- Run `deploy/compose/scripts/check_runtime_contract.sh` and
  `deploy/compose/scripts/validate_stack.sh` when runbook changes touch runtime
  contract or Compose input guidance.
