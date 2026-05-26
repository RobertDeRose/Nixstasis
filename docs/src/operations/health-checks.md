# Health Checks

Run these checks after deployment, restore, secret rotation, upgrade, or incident
response.

## Static Contract Checks

```sh
deploy/compose/scripts/check_runtime_contract.sh
deploy/compose/scripts/validate_stack.sh deploy/compose/.env
```

`check_runtime_contract.sh` checks source-controlled deployment contract drift.
`validate_stack.sh` checks the operator `.env`, Caddy policy shape, and rendered
Compose stack, then runs Docker Compose build validation. It requires a working
Docker daemon.

## Compose Services

```sh
cd deploy/compose
docker compose --env-file .env ps
docker compose --env-file .env logs --tail=100 nixstasis caddy frps postgres
```

All production services should be running or healthy. Investigate repeated
restarts before proceeding with application-level checks.

## Phoenix Through Caddy

- Visit `https://nixstasis.<base-domain>` through Caddy.
- Confirm operator authentication completes through AuthCrunch.
- Confirm allowed OIDC groups are transformed by Caddy into the expected
  normalized role. `nixstasis/viewer` should not be able to start remote access
  or manage reports; `nixstasis/operator` and `nixstasis/admin` may use the
  currently implemented operational controls.
- Confirm LiveView pages load without origin or session errors.
- Confirm migrations have been run explicitly with `/app/bin/migrate`.

## Caddy TLS And Domain Approval

- Confirm Caddy can reach `http://nixstasis:${PORT}/api/v1/check_domain`.
- Confirm device wildcard hostnames are authorized before Caddy proxies them to
  FRPS.
- Confirm unauthorized wildcard hostnames are denied.

## FRPS

- Confirm the `frps` service starts with numeric FRP ports and required token and
  dashboard credentials.
- Confirm `frp-admin.<base-domain>` is reachable only through Caddy auth.
- Confirm a managed client can establish FRPC connectivity when remote access is
  requested.

## PostgreSQL

- Confirm the host and port in `DATABASE_URL` accept connections.
- Confirm `/app/bin/migrate` exits successfully.
- Confirm the Phoenix service does not log repeated database connection failures.

## Device Freshness And Remote Access

- Confirm approved devices continue sending heartbeats.
- Confirm stale devices produce expected offline behavior.
- From `/devices/:id`, request remote access and validate terminal startup through
  the browser UI.

## E2E Retention

- Confirm E2E endpoints are disabled in production unless intentionally enabled
  with `NIXSTASIS_E2E_ENABLED=true` for staging validation.
- Confirm retention logs do not show repeated pruning failures.
- Confirm E2E result pages remain available for retained runs when E2E is enabled.
