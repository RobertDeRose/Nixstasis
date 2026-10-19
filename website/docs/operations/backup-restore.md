# Backup And Restore

A Nixstasis deployment keeps its data in two places, and a complete backup needs both:

- **PostgreSQL** holds the application data: devices, commands, telemetry, alerts, reports, settings, and provisioning
  records.
- **Two Caddy volumes**, `caddy-data` and `caddy-config`, hold Caddy's certificates and plugin state under `/data` and
  `/config`.

A database backup on its own does not include Caddy's state.

## Before You Begin

- Check whether `DATABASE_URL` points at the bundled `postgres` service or an external database.
- Note the image digests and `.env` values the stack is running with.
- Pick a backup directory outside the repository, such as `/var/backups/nixstasis`, and protect it like any other
  production secret.
- Remember that the server never runs migrations on startup; you run them yourself.

## Bundled PostgreSQL Backup

Take a dump from the `postgres` service:

```sh
cd deploy/compose
docker compose --env-file .env exec -T postgres \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > /var/backups/nixstasis/nixstasis-$(date +%Y%m%d%H%M%S).dump
```

The `sh -c` wrapper makes the database variables expand inside the container, where Compose has set them, rather than
in your own shell.

## Caddy State Backup

Stop Caddy while you copy its volumes, so the archive is a consistent snapshot. Everything else can keep running, but
the web UI is unreachable until Caddy is back.

```sh
cd deploy/compose
backup_dir=/var/backups/nixstasis
archive=caddy-$(date +%Y%m%d%H%M%S).tar.gz
mkdir -p "$backup_dir"

docker compose --env-file .env stop caddy
backup_status=0
docker compose --env-file .env run --rm --no-deps \
  -e CADDY_BACKUP_ARCHIVE="$archive" \
  -v "$backup_dir:/backup" \
  --entrypoint /bin/sh caddy \
  -c 'tar -C / -czf "/backup/$CADDY_BACKUP_ARCHIVE" data config && \
      chmod 0600 "/backup/$CADDY_BACKUP_ARCHIVE"' || backup_status=$?
docker compose --env-file .env start caddy
test "$backup_status" -eq 0
```

Caddy is started again even if the archive step fails, and the final `test` then reports the failure, so a script
running this never thinks it succeeded.

The archive holds everything in `/data` and `/config`, including TLS keys. Keep it as safe as your secrets.

## Bundled PostgreSQL Restore

Restore into a fresh PostgreSQL volume or an empty database. `pg_restore --clean` only removes objects that are in the
dump, so anything created after the backup would be left behind.

Stop everything that writes to the database first, so no request lands halfway through:

```sh
cd deploy/compose
docker compose --env-file .env stop nixstasis caddy
docker compose --env-file .env up -d postgres
docker compose --env-file .env exec -T postgres \
  sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
  < /path/to/nixstasis.dump
docker compose --env-file .env run --rm nixstasis /app/bin/migrate
```

Restore Caddy state before bringing the complete stack back online.

## Caddy State Restore

Where you can, use the Caddy archive taken at the same time as the database backup. Restoring replaces everything in
both volumes. To make that safe, the script first unpacks the archive into a temporary directory and checks it has both
`data` and `config`. Only then does it clear the volumes, and if any step fails the stack stays stopped.

```sh
cd deploy/compose
backup_dir=/var/backups/nixstasis
archive=caddy-YYYYMMDDHHMMSS.tar.gz

docker compose --env-file .env stop caddy &&
docker compose --env-file .env run --rm --no-deps \
  -e CADDY_BACKUP_ARCHIVE="$archive" \
  -v "$backup_dir:/backup:ro" \
  --entrypoint /bin/sh caddy \
  -euc 'staging=$(mktemp -d)
        tar -C "$staging" -xzf "/backup/$CADDY_BACKUP_ARCHIVE"
        test -d "$staging/data" && test -d "$staging/config"
        rm -rf /data/* /data/.[!.]* /data/..?* /config/* /config/.[!.]* /config/..?*
        cp -a "$staging/data/." /data/
        cp -a "$staging/config/." /config/
        rm -rf "$staging"' &&
docker compose --env-file .env up -d
```

After restore, run the health checks in [Health Checks](health-checks.md).

## External PostgreSQL

With an external managed database, use that platform's backup and point-in-time recovery tools. You still need to:

- keep a record of the exact `DATABASE_URL` and credentials the server uses;
- back up and restore the Caddy volumes yourself, since the database platform knows nothing about them;
- run `/app/bin/migrate` after a restore if the recovered database might be older than the running release;
- check the server, Caddy, FRPS, recent device heartbeats, and remote access once everything is restored.

## Test your backups

A backup you have never restored is a guess. Restore into a non-production stack at least once, then confirm:

- the server starts and can reach PostgreSQL;
- Caddy routes to the server, and certificate approval still reaches `GET /api/v1/check_domain`;
- Caddy's certificates and sign-in state came through;
- devices, alert history, reports, and E2E records match the point you restored to.
