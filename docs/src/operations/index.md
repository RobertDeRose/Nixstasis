# Production Operations

These runbooks cover the supported production Compose deployment for Nixstasis.
They are operator-facing procedures for keeping the stack recoverable,
observable, and safe to change.

Use these runbooks with the deployment contract in
`deploy/compose/README.md` and the runtime boundary docs in
[Runtime Boundaries](../runtime-boundaries.md).

## Supported Deployment Shape

- Production server deployment uses `deploy/compose/docker-compose.yml`.
- Operator configuration starts from `deploy/compose/.env.example` and is copied
  to a git-ignored `.env` file.
- Production image refs should be digest-pinned GHCR references, not mutable tags.
- Phoenix is publicly reachable through Caddy; Caddy owns public HTTP(S) ingress.
- FRPS supports managed-device tunnels and browser-launched terminal flows.
- PostgreSQL can be the bundled Compose service or an external managed database
  referenced by `DATABASE_URL`.

## Runbooks

- [Backup And Restore](backup-restore.md)
- [Secret Rotation](secret-rotation.md)
- [Health Checks](health-checks.md)
- [Command Policies](command-policies.md)
- [Incident Response](incidents.md)
- [Upgrades And Rollbacks](upgrades-rollbacks.md)
- [HA And Scaling](ha-scaling.md)

## Validation Scripts

Run these from the repository root when changing deployment inputs or validating
a production `.env` file:

```sh
deploy/compose/scripts/check_runtime_contract.sh
deploy/compose/scripts/validate_stack.sh deploy/compose/.env
```

`check_runtime_contract.sh` validates repository contract drift. `validate_stack.sh`
validates the operator production `.env`, requires
`CADDY_CONFIG=./caddy/Caddyfile`, checks the production Caddy policy shape and
rendered stack, then runs Docker Compose build validation. It requires a working
Docker daemon.
