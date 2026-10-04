# Backup And Restore

Nixstasis has two durable state domains in the supported Compose deployment:

- PostgreSQL stores application state such as devices, commands, telemetry,
  alerts, reports, settings, and provisioning metadata.
- The named Caddy volumes `caddy-data` and `caddy-config` store Caddy TLS and
  plugin-owned state under `/data` and `/config`.

A complete bundled-stack backup preserves both domains. Backing up PostgreSQL
alone does not preserve Caddy's persisted state.

## Before You Begin

- Identify whether `DATABASE_URL` points to the bundled Compose `postgres` service
  or an external PostgreSQL host.
- Record the image digests and `.env` values used by the running stack.
- Keep backup files outside the repository and protect them like production
  secrets.
- Choose an operator-controlled backup directory outside the repository, such as
  `/var/backups/nixstasis`.
- Run migrations explicitly; application startup does not run migrations.

## Bundled PostgreSQL Backup

For the bundled Compose database, take a logical dump from the `postgres` service:

```sh
cd deploy/compose
docker compose --env-file .env exec -T postgres \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > /var/backups/nixstasis/nixstasis-$(date +%Y%m%d%H%M%S).dump
```

The `sh -c` wrapper expands database variables inside the container environment
loaded by Compose, not in the operator's host shell. Store the dump in an
operator-controlled backup location.

## Caddy State Backup

Stop Caddy while copying its named volumes so the archive represents one
consistent state. Phoenix, PostgreSQL, and FRPS can remain running while Caddy is
stopped, but browser traffic is unavailable during this step.

```sh
cd deploy/compose
backup_dir=/var/backups/nixstasis
archive=caddy-$(date +%Y%m%d%H%M%S).tar.gz
mkdir -p "$backup_dir"

docker compose --env-file .env stop caddy
docker compose --env-file .env run --rm --no-deps \
  -e CADDY_BACKUP_ARCHIVE="$archive" \
  -v "$backup_dir:/backup" \
  --entrypoint /bin/sh caddy \
  -c 'tar -C / -czf "/backup/$CADDY_BACKUP_ARCHIVE" data config && \
      chmod 0600 "/backup/$CADDY_BACKUP_ARCHIVE"'
docker compose --env-file .env start caddy
```

The archive contains the contents mounted at `/data` and `/config`, including
TLS and plugin-owned state. Treat it as sensitive operational state.

## Bundled PostgreSQL Restore

Restore into a disposable or recovered stack before declaring the backup valid.
Use a fresh PostgreSQL volume or an empty target database; `pg_restore --clean`
does not remove objects that were created after the backup and are absent from
the dump.

```sh
cd deploy/compose
docker compose --env-file .env up -d postgres
docker compose --env-file .env exec -T postgres \
  sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
  < /path/to/nixstasis.dump
docker compose --env-file .env run --rm nixstasis /app/bin/migrate
```

Restore Caddy state before bringing the complete stack back online.

## Caddy State Restore

Use the Caddy archive from the same recovery point as the database backup when
possible. Restoring a Caddy archive replaces the current contents of both named
volumes.

```sh
cd deploy/compose
backup_dir=/var/backups/nixstasis
archive=caddy-YYYYMMDDHHMMSS.tar.gz

docker compose --env-file .env stop caddy
docker compose --env-file .env run --rm --no-deps \
  -e CADDY_BACKUP_ARCHIVE="$archive" \
  -v "$backup_dir:/backup:ro" \
  --entrypoint /bin/sh caddy \
  -c 'rm -rf /data/* /data/.[!.]* /data/..?* /config/* /config/.[!.]* /config/..?*; \
      tar -C / -xzf "/backup/$CADDY_BACKUP_ARCHIVE"'
docker compose --env-file .env up -d
```

After restore, run the health checks in [Health Checks](health-checks.md).

## External PostgreSQL

When `DATABASE_URL` points to an external managed database, use that platform's
backup and point-in-time recovery tooling. Nixstasis runbook responsibilities are:

- Preserve the exact `DATABASE_URL` target and credentials needed by the Phoenix
  service.
- Back up and restore the Compose-managed Caddy `caddy-data` and `caddy-config`
  volumes independently of the managed PostgreSQL platform.
- Run `/app/bin/migrate` after restore if the recovered database may predate the
  current release.
- Validate Phoenix, Caddy, FRPS, device heartbeat freshness, and remote access
  after the database and Caddy state are restored.

## Validation

- Restore into a non-production stack at least once before relying on a backup
  procedure.
- Confirm the Phoenix application starts and can reach PostgreSQL.
- Confirm Caddy routes to Phoenix and Caddy TLS approval still reaches
  `GET /api/v1/check_domain`.
- Confirm expected Caddy certificates and authentication/plugin state survived
  the restore.
- Confirm device data, alert history, reports, and E2E records match the expected
  restore point.
