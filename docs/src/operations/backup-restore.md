# Backup And Restore

Nixstasis stores durable server state in PostgreSQL. Backups should be logical
database backups unless an operator's managed PostgreSQL platform requires a
different backup primitive.

## Before You Begin

- Identify whether `DATABASE_URL` points to the bundled Compose `postgres` service
  or an external PostgreSQL host.
- Record the image digests and `.env` values used by the running stack.
- Keep backup files outside the repository and protect them like production
  secrets.
- Run migrations explicitly; application startup does not run migrations.

## Bundled PostgreSQL Backup

For the bundled Compose database, take a logical dump from the `postgres` service:

```sh
cd deploy/compose
docker compose --env-file .env exec -T postgres \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > nixstasis-$(date +%Y%m%d%H%M%S).dump
```

The `sh -c` wrapper expands database variables inside the container environment
loaded by Compose, not in the operator's host shell. Store the dump in an
operator-controlled backup location.

## Bundled PostgreSQL Restore

Restore into a disposable or recovered stack before declaring the backup valid:

```sh
cd deploy/compose
docker compose --env-file .env up -d postgres
docker compose --env-file .env exec -T postgres \
  sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
  < /path/to/nixstasis.dump
docker compose --env-file .env run --rm nixstasis /app/bin/migrate
docker compose --env-file .env up -d
```

After restore, run the health checks in [Health Checks](health-checks.md).

## External PostgreSQL

When `DATABASE_URL` points to an external managed database, use that platform's
backup and point-in-time recovery tooling. Nixstasis runbook responsibilities are:

- Preserve the exact `DATABASE_URL` target and credentials needed by the Phoenix
  service.
- Run `/app/bin/migrate` after restore if the recovered database may predate the
  current release.
- Validate Phoenix, Caddy, FRPS, device heartbeat freshness, and remote access
  after the database is restored.

## Validation

- Restore into a non-production stack at least once before relying on a backup
  procedure.
- Confirm the Phoenix application starts and can reach PostgreSQL.
- Confirm Caddy routes to Phoenix and Caddy TLS approval still reaches
  `GET /api/v1/check_domain`.
- Confirm device data, alert history, reports, and E2E records match the expected
  restore point.
