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
`AUTHORIZED_GROUPS`, `NIXSTASIS_VIEWER_GROUPS`, `NIXSTASIS_OPERATOR_GROUPS`,
`NIXSTASIS_ADMIN_GROUPS`, and `JWT_KEY` are consumed by `caddy`.

1. Update the identity provider or AuthCrunch configuration first.
2. Update `.env` with the replacement values.
3. Restart `caddy`.
4. Validate allowed operators can log in and unauthorized roles or groups are
   denied.
5. Validate Caddy transforms the new OIDC groups into the expected
   `nixstasis/*` roles and Phoenix receives those roles through AuthCrunch
   `X-Token-*` claim headers. `nixstasis/viewer` is read-only,
   `nixstasis/operator` can use implemented operational controls, and only
   `nixstasis/admin` can change global system settings.

Avoid wildcard role or group values. `validate_stack.sh` rejects wildcard
authorization inputs.

## Caddy-To-Phoenix Proxy Credential

`NIXSTASIS_PROXY_AUTH_TOKEN` is consumed only by `caddy` and `nixstasis`. It
authenticates the source of AuthCrunch `X-Token-*` claim headers. Generate it
with `openssl rand -hex 32`; do not reuse `JWT_KEY` or a
Phoenix secret.

1. Generate a fresh value and update `NIXSTASIS_PROXY_AUTH_TOKEN` in `.env`.
2. Recreate `caddy` and `nixstasis` together so both sides use the same value.
3. Validate browser login through Caddy.
4. Confirm a direct request to the loopback Phoenix port with only a forged
   `X-Token-User-Roles` header is denied.

## Managed-Device Runtime Tokens

Managed-device runtime tokens are stored only as hashes on the server and as the
clear token in the device identity file. Runtime requests carry the token only in
`Authorization: Bearer <device-token>`; query-string device credentials are
rejected.

If a token may have been retained in historical request URLs, rotate it by
re-registering that device with proof of the current token. Stop the poller while
rotating so the old in-memory credential is not reused:

```sh
sudo systemctl stop nixstasis-poll
sudo -u nixstasis /usr/bin/nixstasis register
sudo systemctl start nixstasis-poll
```

After rotation, verify the device resumes heartbeats and review or purge retained
proxy/APM/support artifacts according to their retention policy.

## FRPS Secrets

FRPS device credentials are signed from `SECRET_KEY_BASE` and bounded by their
lease expiry and maximum signing age. There is no separate device-visible FRPS
shared secret to rotate. If credentials may have been exposed, rotate
`SECRET_KEY_BASE` and restart `nixstasis`. Credentials signed with the old key
then fail signature verification immediately for new `Login` and `NewProxy`
operations; their remaining validity window is not a grace period.

Established tunnels are not forcibly disconnected by signing-key rotation.
FRPC reconnects or new proxy registrations using the old credential fail until
the client installs a replacement. Authenticated heartbeats provide freshly
signed credentials, but signature-only changes do not immediately restart FRPC.
For session-owned access, close and re-open only still-required sessions so a
new lease becomes selected; the client installs its credential at the next
authenticated heartbeat. A higher-priority provisioning lease must be handled
through delivery reconciliation, not replaced by reopening a browser session.
Near-expiry renewal can also install a replacement when the advertised credential
expiry extends beyond the installed deadline; do not assume every heartbeat
reloads the credential or extends its lease.

`FRPS_DASHBOARD_USER` and `FRPS_DASHBOARD_PASSWORD` are FRPS dashboard
credentials consumed by `frps`. Caddy protects the dashboard route with
AuthCrunch and proxies it to FRPS.

1. Update dashboard credentials in `.env`.
2. Restart `frps`.
3. Validate `frp-admin.<base-domain>` through Caddy authentication and FRPS
   dashboard login.

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
