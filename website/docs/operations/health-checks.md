# Health Checks

Run these checks after a deployment, restore, secret rotation, upgrade, or incident. Except where noted, run the
commands from `deploy/compose` with the production `.env`. Each section says what a healthy result looks like.

## Configuration

From the repository root:

```sh
deploy/compose/scripts/validate_stack.sh deploy/compose/.env
```

The script validates the `.env`, requires `CADDY_CONFIG=./caddy/Caddyfile`, checks the production Caddy policy and the
rendered stack, and runs a Compose build. It needs a working Docker daemon. Healthy: it exits `0`.

## Services

```sh
docker compose --env-file .env ps
docker compose --env-file .env logs --tail=100 nixstasis caddy frps postgres
```

Healthy: `nixstasis`, `caddy`, and `frps` are running, `postgres` is `healthy`, and nothing restarts repeatedly. Fix
repeated restarts before checking anything else.

## Database

```sh
docker compose --env-file .env run --rm nixstasis /app/bin/migrate
```

Healthy: migrations exit `0`, and the `nixstasis` logs show no repeated database connection errors.

## Server

The server listens only on loopback, and redirects plain HTTP unless the request says it came through HTTPS:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:${PORT:-4000}/api/v1/check_domain?domain=nixstasis.<base-domain>"
```

Healthy: `204`. The reserved `nixstasis`, `auth`, and `frp-admin` hosts are always approved.

## Certificate approval for device hosts

Run the same request with a device host:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:${PORT:-4000}/api/v1/check_domain?domain=atom-<normalized-device-id>.<base-domain>"
```

Healthy: `401` when the device has no active remote-access lease, and `204` while it has one. A malformed host is
always `401`.

## Operator sign-in and roles

In a browser, open `https://nixstasis.<base-domain>`. Healthy:

- sign-in completes through AuthCrunch and LiveView pages load without origin or session errors;
- a `nixstasis/viewer` user cannot start remote access or manage reports, and an operator or admin can;
- `https://frp-admin.<base-domain>` is refused for viewers and operators before the FRPS login, and reachable for admins.

The capabilities of each role are in the [Operator Role Contract](../reference/contracts.md#operator-role-contract).

## Device heartbeats

Count approved devices that have not reported within the offline window, 10 minutes by default:

```sh
docker compose --env-file .env exec postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "select count(*) from devices
     where approval_status = '\''approved'\''
     and (last_seen_at is null or last_seen_at < now() - interval '\''10 minutes'\'')"'
```

Healthy: the count matches the devices you expect to be offline, and the Devices page shows the same devices as
offline.

## Remote access

From a device's page, open remote access and start a terminal. Healthy: the device starts `frpc` on its next heartbeat,
normally within 30 seconds, and the terminal opens. If it does not, check the FRPS logs and
[Incident Response](incidents.md).

## E2E

Healthy: the E2E API is disabled unless `NIXSTASIS_E2E_ENABLED=true`. When it is enabled for staging,
`NIXSTASIS_E2E_RUNNER_ID` and a fresh `NIXSTASIS_E2E_RUNNER_TOKEN` of at least 32 bytes are set, a request without the
runner credential gets `401`, and the logs show no repeated retention errors.
