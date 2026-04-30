# Nixstasis Compose Deployment

This directory is the supported server deployment path for this feature.

## Runtime contract

- Public ingress always terminates at `caddy`.
- Phoenix runs internally on `PORT=4000` by default.
- Database migrations are explicit and are not part of container startup.
- All external runtime artifacts must be pinned immutably.

## Pinned artifacts

- `frps` must use an image digest via `FRPS_IMAGE_DIGEST`.
- `postgres` must use an image digest via `POSTGRES_IMAGE_DIGEST`.
- Server and Caddy images should be published as `nixstasis`-named OCI images.

## First run

1. Copy `.env.example` to `.env` and fill every required value.
2. Start the stack with `docker compose up -d --build`.
3. Run migrations with `docker compose run --rm nixstasis bin/migrate`.
4. Confirm the `caddy`, `nixstasis`, `frps`, and `postgres` services are healthy.

## External PostgreSQL

When using an external PostgreSQL service, keep the same application contract and
point `DATABASE_URL` at the external server. The bundled `postgres` service
becomes optional for that deployment.
