# Nixstasis Compose Deployment

Single `docker-compose.yml` for both production and local development.
Environment variables are passed via `docker compose --env-file <file>`.
No `env_file:` directives in the compose file — each service declares the
variables it needs in its `environment:` block.

## Services

| Service    | Description                                    |
|------------|------------------------------------------------|
| `nixstasis`| Phoenix server                                 |
| `postgres` | PostgreSQL database                            |
| `caddy`    | Reverse proxy, TLS termination, AuthCrunch     |
| `frps`     | FRP server for NAT-busting device tunnels      |
| `client`   | Device simulator (systemd + sshd + frpc + client binary) |

## Quick Start (Development)

```sh
deploy/compose/scripts/dev-lab.sh up --devices 3
```

This builds all images locally, starts the stack, runs migrations, and seeds
3 virtual devices. Open `http://127.0.0.1:4000` when it finishes.

```sh
deploy/compose/scripts/dev-lab.sh down
```

### dev-lab.sh passthrough

Any command not recognized by `dev-lab.sh` is forwarded to `docker compose`
with the correct project name, compose file, and env file:

```sh
deploy/compose/scripts/dev-lab.sh logs -f nixstasis
deploy/compose/scripts/dev-lab.sh ps
deploy/compose/scripts/dev-lab.sh exec nixstasis /bin/bash
```

### Options

| Flag         | Default | Description                          |
|--------------|---------|--------------------------------------|
| `--devices N`| 3       | Number of virtual devices to seed    |
| `--clients N`| 1       | Number of client containers to start |

## Production

1. Copy `.env.example` to `.env` and fill every required value, including `DATABASE_URL`, `BASE_DOMAIN`, `AUTHORIZED_ROLES`, and `AUTHORIZED_GROUPS`.
2. Set `BIND_HOST=0.0.0.0` and `CADDY_CONFIG=./caddy/Caddyfile`.
3. Set image refs to digest-pinned GHCR references.
4. Start: `docker compose --env-file .env up -d`
5. Run migrations: `docker compose run --rm nixstasis /app/bin/migrate`

For an external PostgreSQL instance, point `DATABASE_URL` at the managed
database. The bundled PostgreSQL service will start but can be ignored or
removed. When using the bundled PostgreSQL service, keep `DATABASE_URL`
targeting the compose `postgres` host.

## Environment Files

| File            | Purpose                              |
|-----------------|--------------------------------------|
| `dev.env`       | Tracked defaults for local dev       |
| `.env.example`  | Template for production              |
| `.env`          | Operator-created, git-ignored        |

### Key env vars that differ between dev and prod

| Variable             | Dev                          | Prod                        |
|----------------------|------------------------------|-----------------------------|
| `BIND_HOST`          | `127.0.0.1`                  | `0.0.0.0`                   |
| `CADDY_CONFIG`       | `./caddy/Caddyfile.laptop`   | `./caddy/Caddyfile`         |
| `CHECK_ORIGIN_EXTRA` | `localhost,127.0.0.1`        | (unset)                     |
| `NIXSTASIS_FORCE_SSL`| `false`                      | (unset, defaults to true)   |
| `*_IMAGE_REF`        | Local tags (`*:dev`)         | Digest-pinned GHCR refs     |

## Runtime Contract

- Public ingress terminates at Caddy.
- Phoenix runs on `PORT=4000` internally.
- Caddy TLS approval: `GET /api/v1/check_domain`.
- Caddy asks `http://nixstasis:${PORT}/api/v1/check_domain` before issuing device certs.
- Reserved hosts: `nixstasis.<base-domain>`, `auth.<base-domain>`,
  `frp-admin.<base-domain>`.
- Wildcard device hosts require `authorize with entra_policy` before proxying.
- AuthCrunch policy must allow roles `${AUTHORIZED_ROLES}` and groups `${AUTHORIZED_GROUPS}`.
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

The client registers with the server, polls for commands, and manages SSH
key authorization and FRP tunnels — the same lifecycle as a real device.

Scale client containers with `--clients N` or `docker compose --scale client=N`.

## Troubleshooting

- If `.localhost` names fail, confirm the browser resolves them to loopback.
- If the server shows origin check errors, ensure `CHECK_ORIGIN_EXTRA` includes
  the hostname you're accessing (e.g. `localhost`).
- On macOS, if Docker network creation fails, use
  [Colima](https://github.com/abiosoft/colima) (`colima start --cpu 2 --memory 4`).
- The client container requires `privileged: true` for systemd. If your runtime
  doesn't support this, the client won't start.

## Contract Validation

```sh
deploy/compose/scripts/check_runtime_contract.sh
deploy/compose/scripts/validate_stack.sh
```
