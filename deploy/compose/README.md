# Nixstasis Compose Deployment

This directory is the supported server deployment path for this feature.

## Runtime contract

- Public ingress always terminates at `caddy`.
- Phoenix runs internally on `PORT=4000` by default.
- The canonical TLS approval path is `GET /api/v1/check_domain`.
- Reserved public hosts are `nixstasis.<base-domain>`,
  `auth.<base-domain>`, and `frp-admin.<base-domain>`.
- Database migrations are explicit and are not part of container startup.
- E2E validation endpoints are disabled by default in production. Enable them
  only for staging validation with `NIXSTASIS_E2E_ENABLED=true`.
- All external runtime artifacts must be pinned immutably.
- Required operator inputs are `DATABASE_URL`, `SECRET_KEY_BASE`,
  `PHX_HOST`, `PORT`, `BASE_DOMAIN`, `CLIENT_ID`, `CLIENT_SECRET`,
  `TENANT_ID`, `JWT_KEY`, `FRPS_BIND_PORT`, `FRPS_AUTH_TOKEN`,
  `FRPS_HTTP_PORT`, `FRPS_DASHBOARD_PORT`, `FRPS_DASHBOARD_USER`,
  `FRPS_DASHBOARD_PASSWORD`, and `FRPS_TCPMUX_PORT`.

## Supported operation

- The supported server deployment flow is `deploy/compose` only.
- `NIXSTASIS_SERVER_IMAGE_REF` and `NIXSTASIS_CADDY_IMAGE_REF` must be set in
  `.env` as immutable digest references before Compose commands are run.
- Bring up the default bundled PostgreSQL stack with:
  `docker compose --profile bundled-db up -d --build`
- Apple Container equivalent:
  `tmp_compose=$(mktemp deploy/compose/.nixstasis-compose.XXXXXX.yml)`
  `&& deploy/compose/scripts/render_compose.sh deploy/compose/.env "$tmp_compose"`
  `&& container-compose up -f "$tmp_compose" --env-file deploy/compose/.env -d --build`
- To use an external PostgreSQL instance, omit the `bundled-db` profile and point
  `DATABASE_URL` at the managed database.
- Run migrations explicitly with:
  `docker compose run --rm nixstasis bin/migrate`
- Apple Container does not provide a `compose run` equivalent, so run the
  migration command with `container run --env-file deploy/compose/.env --entrypoint /app/bin/migrate "$NIXSTASIS_SERVER_IMAGE_REF"`.

## Pinned artifacts

- `frps` is built from this repo and must use the tracked `FRP_VERSION` from `prod.env`.
- `postgres` must use an image digest via `POSTGRES_IMAGE_DIGEST`.
- Server, Caddy, and FRPS image refs must use digest form, such as
  `ghcr.io/<owner>/nixstasis-server@sha256:<digest>`.
- Server and Caddy Dockerfile base images are pinned by the digest values in
  `prod.env`; update the matching version and digest together.
- Server and Caddy images should be published as `nixstasis`-named OCI images.
- Override `NIXSTASIS_SERVER_IMAGE_REF`, `NIXSTASIS_CADDY_IMAGE_REF`, and `NIXSTASIS_FRPS_IMAGE_REF` if operators need
  to consume a different GHCR namespace than the default deployment examples.

## First run

1. Copy `.env.example` to `.env` and fill every required value.
2. Start the stack with `docker compose --profile bundled-db up -d --build`.
   Apple Container equivalent:
   `tmp_compose=$(mktemp deploy/compose/.nixstasis-compose.XXXXXX.yml)`
   `&& deploy/compose/scripts/render_compose.sh deploy/compose/.env "$tmp_compose"`
   `&& container-compose up -f "$tmp_compose" --env-file deploy/compose/.env -d --build`
3. Run migrations with `docker compose run --rm nixstasis bin/migrate`.
4. Confirm the `caddy`, `nixstasis`, `frps`, and `postgres` services are healthy.

## External PostgreSQL

When using an external PostgreSQL service, keep the same application contract and
point `DATABASE_URL` at the external server. The bundled `postgres` service
becomes optional for that deployment.

## Contract validation

- Run `deploy/compose/scripts/check_runtime_contract.sh` to verify the runtime
  contract stays aligned across Compose assets, package examples, and docs.

## Validation

- Run `deploy/compose/scripts/validate_stack.sh` to verify the compose file and
  required services before deployment.

## Release readiness

- OCI image workflows build on branch changes and publish to GHCR on `v*` tags.
- Manual image workflow runs can push only when the `push` input is enabled.
- Client snapshot workflow runs on branch changes or manual dispatch.
- Client release publication runs on `v*` tags only.
- Client workflow reads shared release versions from the tracked `prod.env` file.
- Local validation in this workspace uses Apple `container` and a pinned local
  `FRPC_SOURCE_BINARY`; validate image publication and client release publication
  on GitHub Actions when exercising the `v*` tag flows.
