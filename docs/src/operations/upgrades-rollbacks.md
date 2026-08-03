# Upgrades And Rollbacks

Production upgrades should be deliberate and reversible. Use digest-pinned image
references in `.env`; do not use mutable tags for production service images.

## Preflight

1. Read the release notes for server, Caddy, FRPS, and client artifacts being
   upgraded.
2. Record current image digests from `.env`.
3. Take a database backup.
4. Run static validation:

   ```sh
   deploy/compose/scripts/check_runtime_contract.sh
   deploy/compose/scripts/validate_stack.sh deploy/compose/.env
   ```

5. Confirm operator access through Caddy/AuthCrunch.

## Server Stack Upgrade

1. Update digest-pinned image refs in `.env`.
2. Pull the replacement images without restarting the application yet:

   ```sh
   cd deploy/compose
   docker compose --env-file .env pull
   ```

3. Decide whether the release contains only backward-compatible online
   migrations. If not, enter a maintenance window and stop Caddy or otherwise
   remove public traffic before changing the database schema.
4. Confirm PostgreSQL is available, then run migrations explicitly with the new
   `nixstasis` image:

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

When deploying new managed-device client artifacts:

- Verify release artifact checksums before installation.
- Confirm `/etc/nixstasis/config.yaml` is preserved unless the operator
  intentionally replaces it.
- Confirm the bundled `frpc` path remains `/usr/libexec/nixstasis/frpc`.
- Confirm the client can register or continue polling after upgrade.

## Rollback

Rollback boundaries depend on whether migrations changed the database schema.

If no irreversible migration ran:

1. Restore previous digest-pinned image refs in `.env`.
2. Run `docker compose --env-file .env up -d`.
3. Validate Phoenix, Caddy, FRPS, PostgreSQL, and remote access.

If a migration changed data or schema incompatibly:

1. Restore the database backup into a recovered stack.
2. Restore previous image refs.
3. Run `/app/bin/migrate` for the restored version if required.
4. Run the full health-check sequence.

Do not assume the Compose deployment provides automatic rollback or clustered
zero-downtime upgrade behavior.
