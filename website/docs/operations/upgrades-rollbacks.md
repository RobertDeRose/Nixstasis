# Upgrades And Rollbacks

Plan every upgrade so you can undo it. Pin images by digest in `.env`; a tag like `latest` can change under you, so
never use one in production.

## Preflight

1. Read the release notes for each server, Caddy, FRPS, and client artifact you are upgrading.
2. Write down the current image digests from `.env`, so you can roll back.
3. Take a database backup.
4. Run static validation:

   ```sh
   deploy/compose/scripts/validate_stack.sh deploy/compose/.env
   ```

5. Confirm you can sign in through Caddy.

## Server Stack Upgrade

1. Update digest-pinned image refs in `.env`.
2. Pull the replacement images without restarting the application yet:

   ```sh
   cd deploy/compose
   docker compose --env-file .env pull
   ```

3. Check whether the release's migrations are safe to run while the old version is still serving traffic. If they are
   not, schedule a maintenance window and stop Caddy, or otherwise cut off public traffic, before migrating.
4. Make sure PostgreSQL is running, then run the migrations with the new `nixstasis` image:

   ```sh
   docker compose --env-file .env up -d postgres
   docker compose --env-file .env run --rm nixstasis /app/bin/migrate
   ```

5. Start or restart the full stack:

   ```sh
   docker compose --env-file .env up -d
   ```

6. Run [Health Checks](health-checks.md).

## Client Artifact Upgrade

When you roll out a new client:

- check the release checksums before installing;
- check that `/etc/nixstasis/config.yaml` was kept, unless you meant to replace it;
- check that `frpc` is still at `/usr/libexec/nixstasis/frpc`;
- check that the device can still register or keeps polling.

## Rollback

How you roll back depends on whether the upgrade's migrations changed the database in a way the old version cannot
handle.

If they did not:

1. Restore previous digest-pinned image refs in `.env`.
2. Run `docker compose --env-file .env up -d`.
3. Validate the server, Caddy, FRPS, PostgreSQL, and remote access.

If they did:

1. Restore the database backup into a recovered stack.
2. Restore previous image refs.
3. Run `/app/bin/migrate` for the restored version if required.
4. Run the full health-check sequence.

The Compose deployment has no automatic rollback and no zero-downtime upgrades; see [HA And Scaling](ha-scaling.md).
