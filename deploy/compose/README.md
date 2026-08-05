# Nixstasis Compose Deployment

Single `docker-compose.yml` for both production and local development.
Environment variables are passed via `docker compose --env-file <file>`.
No `env_file:` directives in the compose file — each service declares the
variables it needs in its `environment:` block.

## Services

| Service     | Description                                                    |
|-------------|----------------------------------------------------------------|
| `nixstasis` | Phoenix server                                                 |
| `postgres`  | PostgreSQL database                                            |
| `caddy`     | Reverse proxy, TLS termination, AuthCrunch                     |
| `frps`      | FRP server for NAT-busting device tunnels                      |
| `client`    | Device simulator (systemd + PCP + sshd + frpc + client binary) |

## Quick Start (Development)

```sh
mise run deploy:dev -- up --clients 3
```

This builds all images locally, starts the stack, runs migrations, starts 3
client simulator containers, and pre-approves those real simulator devices.
Open `http://127.0.0.1:4000` when it finishes.

```sh
mise run deploy:dev -- down
```

This removes the dev-lab containers and named volumes, including the local
PostgreSQL data volume. The next `mise run deploy:dev -- up` starts from an
empty database.

The `mise` task exposes the client count as a flag:

```sh
mise run deploy:dev -- up --clients 2
```

`up` is the dev-lab bootstrap command: it starts Postgres, runs migrations,
starts the full stack, scales client containers, and pre-approves the running
client simulators. Seed deterministic schema-builder fixtures into the running
Compose database with:

```sh
mise run deploy:dev:seed
```

The seed task is idempotent for its stable devices, alert, report, and telemetry
batch. Add future fixtures in `.mise/tasks/deploy/dev/seed.sh` with a new stable
identifier or telemetry marker. It requires the dev lab to be running and uses
Compose `exec`; it does not connect to a host PostgreSQL port.

Other commands pass through to Docker Compose, so use normal Compose commands such as
`mise run deploy:dev -- logs -f`, `mise run deploy:dev -- logs -f client`,
`mise run deploy:dev -- logs -f client1`, `mise run deploy:dev -- ps`, and
`mise run deploy:dev -- down`. The `client1`/`client2` log shorthand maps to
Compose's native `logs --index N client` form.

### deploy:dev passthrough

Any command not recognized by `.mise/tasks/deploy/dev.sh` is forwarded to `docker compose`
with the correct project name, compose file, and env file:

```sh
mise run deploy:dev -- logs -f nixstasis
mise run deploy:dev -- logs -f client1
mise run deploy:dev -- ps
mise run deploy:dev -- client-logs --index 1 -n 100
mise run deploy:dev -- exec nixstasis /bin/bash
```

### Options

| Flag          | Default | Description                                  |
|---------------|---------|----------------------------------------------|
| `--clients N` | 1       | Number of real Go client containers to start |

## Production

1. Copy `.env.example` to `.env` and fill every required value, including `DATABASE_URL`, `BASE_DOMAIN`, `AUTHORIZED_ROLES`, `AUTHORIZED_GROUPS`, and the `NIXSTASIS_*_GROUPS` group-to-role mapping values.
2. Set `BIND_HOST=0.0.0.0`, keep `PHOENIX_BIND_HOST=127.0.0.1`, and set `CADDY_CONFIG=./caddy/Caddyfile`.
3. Set image refs to digest-pinned GHCR references.
4. Start: `docker compose --env-file .env up -d`
5. Run migrations: `docker compose run --rm nixstasis /app/bin/migrate`

For an external PostgreSQL instance, point `DATABASE_URL` at the managed
database. The bundled PostgreSQL service will start but can be ignored or
removed. When using the bundled PostgreSQL service, keep `DATABASE_URL`
targeting the compose `postgres` host.

## Environment Files

| File           | Purpose                             |
|----------------|-------------------------------------|
| `dev.env`      | Tracked defaults for local dev/test |
| `.env.example` | Template for production             |
| `.env`         | Operator-created, git-ignored       |

### Key env vars that differ between dev and prod

| Variable                           | Dev                                  | Prod                        |
|------------------------------------|--------------------------------------|-----------------------------|
| `BIND_HOST`                        | `127.0.0.1`                          | `0.0.0.0`                   |
| `PHOENIX_BIND_HOST`                | `127.0.0.1`                          | `127.0.0.1`                 |
| `CADDY_CONFIG`                     | `./caddy/Caddyfile.dev`              | `./caddy/Caddyfile`         |
| `CHECK_ORIGIN_EXTRA`               | `nixstasis.localhost,127.0.0.1:4000` | (unset)                     |
| `NIXSTASIS_FORCE_SSL`              | `false`                              | (unset, defaults to true)   |
| `NIXSTASIS_SESSION_COOKIE_SECURE`  | `false`                              | `true`                      |
| `NIXSTASIS_SIMULATOR_HTTP_ENABLED` | `true`                               | `false`                     |
| `NIXSTASIS_SSH_FRP_HOST`           | `frps`                               | reachable FRPS TCP mux host |
| `*_IMAGE_REF`                      | Local tags (`*:dev`)                 | Digest-pinned GHCR refs     |

## Runtime Contract

- Public ingress terminates at Caddy.
- Phoenix runs on `PORT=4000` internally.
- Phoenix's optional host-published diagnostic port binds to
  `PHOENIX_BIND_HOST=127.0.0.1` by default. Do not expose it publicly in
  production; browser authorization is only supported through Caddy/AuthCrunch.
- `FRPS_AUTH_TOKEN` is provided to both `frps` and `nixstasis`; FRPS uses it for
  token auth, and Phoenix only returns it to authenticated device heartbeats while
  remote access is requested for that device.
- PostgreSQL data is mounted at `/var/lib/postgresql` to match the PostgreSQL 18+
  image layout.
- `FRPS_HTTP_PORT` is an internal Compose port for Caddy wildcard proxying and is
  not published directly on the host.
- `NIXSTASIS_SSH_FRP_HOST` is the hostname Phoenix uses for browser terminal SSH
  connections to FRPS TCP mux. In Compose it should stay `frps`; outside Compose
  it must be the FRPS TCP mux host reachable from the Phoenix runtime.
- The client poll service and root-owned SSH helper use the fixed local socket
  `/run/nixstasis/ssh-authority.sock`; custom socket paths are unsupported.
- The tracked dev/test env uses `./caddy/Caddyfile.dev`, which keeps the stack
  loopback-only and relies on Phoenix's explicit local auth fallback. Use
  `./caddy/Caddyfile.laptop` only when validating AuthCrunch with real OIDC
  credentials.
- The tracked dev/test env builds the Phoenix release with non-secure session
  cookies so the loopback `http://127.0.0.1:4000` diagnostic UI can keep
  LiveView sessions. Production images must keep secure session cookies enabled.
- Caddy TLS approval: `GET /api/v1/check_domain`.
- Caddy asks `http://nixstasis:${PORT}/api/v1/check_domain` before issuing device certs.
- The tracked dev/test Caddyfile uses Caddy's internal CA directly instead of
  on-demand TLS so local HTTPS is deterministic without public ACME or OIDC.
- Reserved hosts: `nixstasis.<base-domain>`, `auth.<base-domain>`,
  `frp-admin.<base-domain>`.
- Wildcard device hosts require `authorize with entra_policy` before proxying.
- AuthCrunch policy must allow roles `${AUTHORIZED_ROLES}` and groups `${AUTHORIZED_GROUPS}`.
- Caddy transforms provider-specific OIDC groups into provider-generic
  Nixstasis roles with `NIXSTASIS_VIEWER_GROUPS`, `NIXSTASIS_OPERATOR_GROUPS`,
  and `NIXSTASIS_ADMIN_GROUPS`. `AUTHORIZED_GROUPS` should include the union of
  those group IDs so the edge authorization policy and role transform stay in
  sync.
- Caddy injects AuthCrunch claims for Phoenix browser UI permission mapping with
  `X-Token-Subject`, `X-Token-User-Email`, `X-Token-User-Name`, and
  `X-Token-User-Roles`. Phoenix consumes only normalized `nixstasis/viewer`,
  `nixstasis/operator`, and `nixstasis/admin` role values; missing or unknown
  production role claims fail closed.
- Migrations are explicit, not part of container startup.

Production image refs should look like `ghcr.io/<owner>/nixstasis-server@sha256:<digest>`.

The container entrypoints wait for the `DATABASE_URL` host and port to accept
connections before the Phoenix release starts or migrations run.

## Client Container

The `client` service is a full device simulator running Ubuntu with systemd
as PID 1. It includes:

- **sshd** — SSH server for remote access testing
- **frpc** — FRP client for tunnel connectivity
- **nixstasis client** — the Go client binary, started via systemd units
- **PCP** — Performance Co-Pilot services (`pmcd`, `pmlogger`) and tools for PCP telemetry validation
- **simulator HTTPS** — local endpoint on `127.0.0.1:443` for FRP HTTP-route smoke tests when `NIXSTASIS_SIMULATOR_HTTP_ENABLED=true`

The client registers with the server, polls for commands, and manages SSH
key authorization and FRP tunnels — the same lifecycle as a real device.
The container entrypoint writes `/etc/nixstasis/config.yaml` from Compose
environment before systemd starts, so the simulator uses the Compose-internal
Phoenix and FRPS hosts instead of the packaged example defaults.
If the image is run with an explicit command instead of systemd, the entrypoint
starts PCP directly before executing that command so PCP tooling can still be
tested in non-systemd container runs.
The image keeps `systemd-user-sessions.service` enabled so `/run/nologin` is
removed during boot and browser SSH terminal sessions can log in as
`nixstasis-support`. The `nixstasis` account remains the service identity, and
`nixstasis-ssh-authority` runs only the narrow key lookup helper. The tracked dev
env enables the simulator HTTPS endpoint so
`atom-<normalized-device-id>.localhost` can traverse Caddy, FRPS, FRPC, and a
real client-local TLS listener. Production env examples keep that endpoint
disabled.

Scale client containers in the dev-lab bootstrap with `--clients N`. In raw
Docker Compose, scaling is done with `--scale client=N`, for example
`docker compose up --scale client=3 client`; Compose does not use `client:3`
syntax.
These are real runtime simulators: each container boots systemd, runs PCP,
runs the Go client, registers with the server, polls for commands, and opens
FRP/SSH routes.
The Device page PCP tab reads PCP-derived samples from heartbeat telemetry. The
FRP-exposed PCP TCP route is for direct remote diagnostics and is available only
while the server has requested remote access for that client, because the client
starts FRPC on demand.
The dev-lab script pre-approves the running client container MAC addresses after
the server is ready; the clients still complete registration themselves and then
poll with issued runtime credentials.

The dev-lab no longer seeds database-only virtual devices. Devices shown after
`up` should correspond to running client simulators or manually installed clients
that registered with the dev-lab server/FRPS.

Client application logs are in journald inside the systemd container, not Docker
stdout. Use
`mise run deploy:dev -- client-logs --index 1 -n 100`.

## Troubleshooting

- If `.localhost` names fail, confirm the browser resolves them to loopback.
- If the server shows origin check errors, ensure `CHECK_ORIGIN_EXTRA` includes
  the hostname you're accessing (e.g. `localhost`).
- On macOS, if Docker network creation fails, use
  [Colima](https://github.com/abiosoft/colima) (`colima start --cpu 2 --memory 4`).
- The client container requires `privileged: true` for systemd. If your runtime
  doesn't support this, the client won't start.
- If client containers stay offline, check `client-logs`; `docker compose logs
  client` only shows the systemd process stdout/stderr.
- If browser SSH terminal sessions end immediately with `pam_nologin`, confirm
  `systemd-user-sessions.service` ran and `/run/nologin` is absent in the client
  container.

## Contract Validation

```sh
deploy/compose/scripts/check_runtime_contract.sh
deploy/compose/scripts/validate_stack.sh deploy/compose/.env
```

`validate_stack.sh` validates production deployment inputs and the production
`./caddy/Caddyfile` policy. Use `mise run deploy:dev -- up` for the local
`dev.env` and `./caddy/Caddyfile.dev` workflow.

## Production Operations

Production backup and restore, secret rotation, health checks, incident response,
upgrade and rollback, and HA boundary runbooks live in
`docs/src/operations/`.
