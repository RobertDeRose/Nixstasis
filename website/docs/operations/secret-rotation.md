# Secret Rotation

Secrets live in `deploy/compose/.env`. Never commit a production `.env`, or any tokens, keys, or backup files.

Every rotation ends the same way: validate the stack, then restart the services that use the secret.

```sh
deploy/compose/scripts/validate_stack.sh deploy/compose/.env
cd deploy/compose
docker compose --env-file .env up -d <service>
```

## Server secret

`SECRET_KEY_BASE` is used by the `nixstasis` service to sign sessions and other state. Changing it signs everyone out.

1. Generate a new secret.
2. Update `SECRET_KEY_BASE` in `.env`.
3. Restart `nixstasis`.
4. Sign in through Caddy and click through a few pages to confirm everything works.

## AuthCrunch and OIDC settings

`caddy` uses `CLIENT_ID`, `CLIENT_SECRET`, `AUTHORIZED_ROLES`, `AUTHORIZED_GROUPS`, `NIXSTASIS_VIEWER_GROUPS`,
`NIXSTASIS_OPERATOR_GROUPS`, `NIXSTASIS_ADMIN_GROUPS`, `JWT_KEY`, and any settings your identity provider's driver
needs, such as `TENANT_ID` in the Microsoft Entra ID example.

1. Make the change in your identity provider or AuthCrunch configuration first.
2. Put the new values in `.env`.
3. Restart `caddy`.
4. Check that allowed operators can sign in, and that people outside the allowed roles or groups cannot.
5. Check that each OIDC group maps to the right Nixstasis role, and that the server receives it:
   - `nixstasis/viewer` can only look;
   - `nixstasis/operator` can use the operational controls;
   - only `nixstasis/admin` can change global settings.

Don't use wildcard role or group values; `validate_stack.sh` rejects them.

## Caddy-to-server proxy credential

`NIXSTASIS_PROXY_AUTH_TOKEN` is shared by `caddy` and `nixstasis` only. It proves to the server that identity headers
really came from Caddy. Generate it with `openssl rand -hex 32`, and don't reuse `JWT_KEY` or the server secret.

1. Generate a new value and put it in `NIXSTASIS_PROXY_AUTH_TOKEN` in `.env`.
2. Recreate `caddy` and `nixstasis` together, so both use the same value.
3. Sign in through Caddy.
4. Send a request straight to the server's loopback port with a made-up `X-Token-User-Roles` header, and confirm it is
   refused.

## Device runtime tokens

The server stores only a hash of each device's runtime token; the device keeps the token itself in its identity file.
Devices send it only in the `Authorization: Bearer <device-token>` header, and the server rejects tokens in a URL.

If a token might have been captured, for example in old request URLs, have the device register again using its
current token. Stop the poller first so it does not keep using the old token from memory:

```sh
sudo systemctl stop nixstasis-poll
sudo -u nixstasis /usr/bin/nixstasis register
sudo systemctl start nixstasis-poll
```

Afterwards, check that the device is sending heartbeats again, and clean up any proxy, APM, or support logs that kept
the old token, according to their retention rules.

## FRPS device credentials

There is no shared FRPS secret to rotate. Each device's FRPS credential is signed with `SECRET_KEY_BASE`, and expires
with its lease or when it reaches the maximum signing age. If credentials may have leaked, rotate `SECRET_KEY_BASE`
and restart `nixstasis`. From then on, FRPS refuses any new login or proxy that uses an old credential, even if it has
not expired yet.

Rotating the key does not drop tunnels that are already connected. What changes is that an old credential can no
longer reconnect or register a new proxy, so a device needs a new credential before its next reconnect. To get one to
it:

- **Browser sessions:** close and reopen only the sessions you still need. That opens a new lease, and the device picks
  up its credential on the next heartbeat.
- **Provisioning deliveries:** don't open a browser session to replace one. A provisioning lease outranks it; resolve
  the delivery instead.

Don't assume every heartbeat delivers a fresh credential. A new token that differs only in its signature does not
restart `frpc`. The device swaps credentials only when its lease changes, or when a later expiry is offered close to
the current one running out.

## FRPS dashboard login

`frps` uses `FRPS_DASHBOARD_USER` and `FRPS_DASHBOARD_PASSWORD` for its dashboard. Caddy also restricts the dashboard
to `nixstasis/admin`.

1. Update the dashboard credentials in `.env`.
2. Restart `frps`.
3. Open `frp-admin.<base-domain>`, sign in through Caddy, then log in to the dashboard.

## Database credentials

With the bundled database, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` belong to the `postgres` service,
and `nixstasis` uses `DATABASE_URL`.

1. Take a backup.
2. Change the credentials in PostgreSQL with its admin tools.
3. Update `DATABASE_URL` and the matching PostgreSQL variables in `.env`.
4. Restart `nixstasis`. Restart `postgres` only if your change needs it.
5. Run `/app/bin/migrate` to confirm the connection works and the migrations are current.

With an external database, follow that platform's rotation process, and update only `DATABASE_URL`.
