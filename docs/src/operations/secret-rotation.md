# Secret Rotation

Rotate secrets from `deploy/compose/.env`. Do not commit production `.env` files,
tokens, keys, or generated backup files.

After changing `.env`, validate the stack and restart affected services:

```sh
deploy/compose/scripts/validate_stack.sh deploy/compose/.env
cd deploy/compose
docker compose --env-file .env up -d <service>
```

## Phoenix Secrets

`SECRET_KEY_BASE` is consumed by the `nixstasis` service. Rotating it invalidates
signed Phoenix state such as sessions.

1. Generate a new Phoenix secret.
2. Update `SECRET_KEY_BASE` in `.env`.
3. Restart `nixstasis`.
4. Validate login and LiveView navigation through Caddy.

## AuthCrunch And OIDC Inputs

`CLIENT_ID`, `CLIENT_SECRET`, `TENANT_ID`, `AUTHORIZED_ROLES`,
`AUTHORIZED_GROUPS`, and `JWT_KEY` are consumed by `caddy`.

1. Update the identity provider or AuthCrunch configuration first.
2. Update `.env` with the replacement values.
3. Restart `caddy`.
4. Validate allowed operators can log in and unauthorized roles or groups are
   denied.

Avoid wildcard role or group values. `validate_stack.sh` rejects wildcard
authorization inputs.

## FRPS Secrets

`FRPS_AUTH_TOKEN` is consumed by `frps` and `nixstasis`; Phoenix returns it only
to authenticated device heartbeats while remote access is requested.

1. Update `FRPS_AUTH_TOKEN` in `.env`.
2. Restart `frps` and `nixstasis`.
3. Expect existing FRPC sessions to reconnect with the new token after clients
   receive the next remote-access heartbeat response.
4. Validate a browser-launched remote-access session from `/devices/:id`.

`FRPS_DASHBOARD_USER` and `FRPS_DASHBOARD_PASSWORD` are consumed by `frps` and
the authenticated Caddy dashboard route.

1. Update dashboard credentials in `.env`.
2. Restart `frps`.
3. Validate `frp-admin.<base-domain>` through Caddy authentication.

## Database Credentials

For bundled PostgreSQL, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`
belong to the `postgres` service, while `DATABASE_URL` is consumed by
`nixstasis`.

1. Take a backup before rotating database credentials.
2. Change credentials in PostgreSQL using the database's administrative tooling.
3. Update `DATABASE_URL` and matching PostgreSQL variables in `.env`.
4. Restart `nixstasis`; restart `postgres` only when required by the credential
   change path.
5. Run `/app/bin/migrate` as a connectivity and migration-state check.

For external PostgreSQL, follow the managed database platform's rotation process
and update only the Nixstasis `DATABASE_URL` value needed by the Compose stack.
