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

### Device bearer-token transport migration

Releases that move managed-device authentication from the legacy `api_key` query
parameter to `Authorization: Bearer <device-token>` require a coordinated client
and server rollout. The hardened server does not accept query-only credentials,
so an old client will receive `401` after the server is upgraded.

After the compatible client and server are installed, rotate device tokens that
may have appeared in retained proxy, APM, diagnostic, or support-bundle request
URLs. Re-registration proves possession of the current token and returns a new
runtime token. On each device, stop the polling process while rotating so it does
not continue using the old in-memory token:

```sh
sudo systemctl stop nixstasis-poll
sudo -u nixstasis /usr/bin/nixstasis register
sudo systemctl start nixstasis-poll
```

Verify a subsequent heartbeat succeeds and contains no `api_key` query parameter
in proxy or application request metadata.

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
