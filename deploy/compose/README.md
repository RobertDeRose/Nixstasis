# Nixstasis Compose Deployment

This directory is the supported server deployment path for this feature.

## Runtime contract

- Public ingress always terminates at `caddy`.
- Phoenix runs internally on `PORT=4000` for the supported Compose deployment.
- The canonical TLS approval path is `GET /api/v1/check_domain`.
- Reserved public hosts are `nixstasis.<base-domain>`,
  `auth.<base-domain>`, and `frp-admin.<base-domain>`.
- Database migrations are explicit and are not part of container startup.
- E2E validation endpoints are disabled by default in production. Enable them
  only for staging validation with `NIXSTASIS_E2E_ENABLED=true`.
- All external runtime artifacts must be pinned immutably.
- Required operator inputs are `DATABASE_URL`, `SECRET_KEY_BASE`,
  `PHX_HOST`, `PORT`, `BASE_DOMAIN`, `CLIENT_ID`, `CLIENT_SECRET`,
  `TENANT_ID`, `JWT_KEY`, `AUTHORIZED_ROLES`, `AUTHORIZED_GROUPS`,
  `FRPS_BIND_PORT`, `FRPS_AUTH_TOKEN`, `FRPS_HTTP_PORT`,
  `FRPS_DASHBOARD_PORT`, `FRPS_DASHBOARD_USER`,
  `FRPS_DASHBOARD_PASSWORD`, and `FRPS_TCPMUX_PORT`.
- `AUTHORIZED_ROLES` maps to the OIDC `roles` claim and `AUTHORIZED_GROUPS`
  maps to the OIDC `groups` claim. Configure least-privilege values for both;
  wildcard values are rejected by the validation scripts.
- The shared AuthCrunch policy protects `nixstasis.<base-domain>`,
  `frp-admin.<base-domain>`, and wildcard FRP device hosts before proxying.

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
- Server startup and explicit migrations wait for the `DATABASE_URL` host and
  port before booting, which covers both bundled and external PostgreSQL.
- Run migrations explicitly with:
  `docker compose run --rm nixstasis bin/migrate`
- Apple Container does not provide a `compose run` equivalent, so run the
  migration command with `container run --env-file deploy/compose/.env --entrypoint /app/bin/migrate "$NIXSTASIS_SERVER_IMAGE_REF"`.

## Development Laptop Mode

For the fastest local server lab, run:

`deploy/compose/scripts/dev-lab.sh up --devices 3`

That command creates ignored local defaults if needed, starts the bundled laptop
stack, runs migrations, and seeds the requested number of approved virtual
devices so the Phoenix UI has data immediately. Open `http://127.0.0.1:4000`
after it finishes. `https://nixstasis.localhost` is also available for the
Caddy/AuthCrunch-shaped path, but it still uses the local auth policy. Stop the
lab with:

`deploy/compose/scripts/dev-lab.sh down`

Development laptop mode uses Compose file composition to keep local-only routing,
TLS, and image settings separate from the supported production deployment. Keep the
base `docker-compose.yml` production-shaped, then layer a development override for
local image builds, local hostnames, Caddy local certificates, and any developer
ports that should not become production defaults.

The laptop override publishes Phoenix directly on `127.0.0.1:4000` only so local
validation scripts can query token-protected diagnostics without passing through
AuthCrunch. It also sets `NIXSTASIS_FORCE_SSL=false` so Caddy's internal HTTP ask
request and loopback diagnostics are not redirected away from Phoenix.

Start from the tracked templates:

- `deploy/compose/laptop.env.example` contains local-only `.localhost` defaults.
- `deploy/compose/docker-compose.laptop.yml` layers laptop-mode env files,
  development builds, and isolated local volumes onto the base Compose file.
- `deploy/compose/caddy/Caddyfile.laptop` keeps the same Caddy/AuthCrunch routing
  shape while using Caddy internal certificates.

Copy `laptop.env.example` to `laptop.env`, replace secrets, and run laptop-mode
Compose commands with both files, for example:
`docker compose -f docker-compose.yml -f docker-compose.laptop.yml --profile bundled-db --env-file laptop.env up -d --build`

Prepare the client state before starting the stack so the SSH target bind mount
points at an existing authorized-keys file:

- `deploy/compose/scripts/laptop-client.sh prepare` writes local `config.yaml`,
  `frpc.toml`, and `authorized_keys` under `deploy/compose/.laptop-client`.

The tracked helper script wraps the same Compose file set:

- `deploy/compose/scripts/laptop.sh validate` checks the laptop environment,
  Caddy local TLS configuration, loopback port binding, and rendered Compose
  configuration. Placeholder secrets from `laptop.env.example` must be replaced
  before validation passes.
- `deploy/compose/scripts/laptop.sh validate-tls` additionally uses `curl` with
  local host resolution to confirm Caddy serves HTTPS for `nixstasis.localhost`,
  `auth.localhost`, and `frp-admin.localhost` through local/internal
  certificates, verifies certificate SANs for those hosts, and checks
  token-protected Phoenix TLS ask observations with a fresh validation hostname.
- `deploy/compose/scripts/laptop.sh start` validates and starts the bundled-db
  laptop stack.
- `deploy/compose/scripts/laptop.sh stop` stops the laptop stack.

After the stack is running, `deploy/compose/scripts/laptop-client.sh` prepares an
ignored local client state directory and runs the Go client against laptop mode:

- `deploy/compose/scripts/laptop-client.sh prepare` can be rerun at any time to
  refresh local client templates.
- `deploy/compose/scripts/laptop-client.sh register` runs `go run ./cmd/nixstasis
  register` with the laptop config and identity path.
- `deploy/compose/scripts/laptop-client.sh poll` runs the polling loop with the
  laptop FRPC template. Set `NIXSTASIS_FRPC_BINARY_PATH` if `frpc` is not
  installed at the package default path.
- `NIXSTASIS_FRPC_BINARY_PATH=/path/to/frpc deploy/compose/scripts/laptop-client.sh validate-frpc`
  starts a bounded FRPC process with the generated development configuration and
  checks for successful FRPS connection output.

The laptop Compose override also starts a development-only SSH target on
`127.0.0.1:${LAPTOP_SSH_PORT:-2222}`. The generated FRPC template forwards the
device SSH proxy to that target, so browser terminal validation reaches an SSH
server only through the FRP path. The SSH target disables password login and reads
the client-managed `deploy/compose/.laptop-client/authorized_keys` file so the
browser terminal validates the queued key-authorization flow. Set
`LAPTOP_SSH_IMAGE_REF` to a digest-pinned OpenSSH server image before starting the
laptop stack.

The registration path requires the laptop stack to be running and reachable at
`https://nixstasis.localhost`. The first registration may remain pending until the
device is approved in the UI; run `register` again after approval so the client can
persist its issued API token. The `poll` command then uses that token and starts
FRPC when the UI requests remote access for the device.

Default laptop mode reserves these local hostnames:

- `nixstasis.localhost` for the Phoenix app through Caddy.
- `auth.localhost` for AuthCrunch through Caddy.
- `frp-admin.localhost` for the FRPS dashboard through Caddy.
- `atom-<normalized-device-id>.localhost` for device HTTP routes through FRPS
  and Caddy.

Use `BASE_DOMAIN=localhost` and `PHX_HOST=nixstasis.localhost` in laptop-mode
environment files. These names mirror the production reserved-host pattern while
staying local-only and avoiding public DNS requirements.

Laptop-mode Caddy configuration must keep the same ask endpoint,
`http://nixstasis:{$PORT}/api/v1/check_domain`, so dynamic TLS approval remains
observable. It should use Caddy `tls internal` or Caddy local certificates for the
reserved `.localhost` hosts instead of public ACME issuance. Generated
certificates, Caddy state, local keys, DNS tokens, and runtime data must stay out
of source control.

Laptop-mode published ports bind to `127.0.0.1` so Caddy and FRPS are not exposed
to the local network by default.

The development override strategy is:

- Add separate laptop-mode Compose override files rather than mutating
  `docker-compose.yml` for development behavior.
- Keep `.env` image references digest-pinned for production examples; use override
  files for local builds or locally tagged images.
- Keep Phoenix reachable through Caddy for deployment-shaped validation.
- Keep the FRPS template contract based on `BASE_DOMAIN`, with `localhost` as the
  laptop-mode base domain.
- Document any test-device or SSH target shortcuts as development-only behavior.

## Optional Public-Fidelity Validation

Default laptop mode is local-only. Use public-fidelity validation only when you
need to prove public DNS and publicly trusted certificate issuance.

DuckDNS path:

1. Create a DuckDNS hostname and configure DNS updates outside this repository.
2. Store DuckDNS tokens outside source control, such as in an untracked env file or
   password manager.
3. Confirm the selected DuckDNS name can satisfy the Nixstasis hostname contract:
   `nixstasis.<base-domain>`, `auth.<base-domain>`, `frp-admin.<base-domain>`,
   and wildcard device hosts such as `atom-<normalized-device-id>.<base-domain>`.
4. Add DNS records so those names resolve to the public Caddy ingress. If DuckDNS
   cannot provide the needed wildcard or delegated records for your chosen base
   domain, use a real DNS provider instead.
5. Use a Caddy build that includes a DuckDNS-compatible DNS-01 module and configure
   DNS provider credentials only through untracked local env files, shell secrets,
   or a secret manager.
6. Set `BASE_DOMAIN` to the DuckDNS domain and use DNS challenge-capable Caddy
   configuration only for the public-fidelity run.
7. Expect DNS propagation delays and DuckDNS service availability to affect the
   result.

Real-domain path:

1. Use an operator-owned domain and DNS provider credentials controlled by the
   operator.
2. Create or delegate records for `nixstasis.<base-domain>`,
   `auth.<base-domain>`, `frp-admin.<base-domain>`, and wildcard device hosts
   under `<base-domain>` so device hosts reach Caddy.
3. Use a Caddy image that includes the DNS provider module required for DNS-01
   ACME challenges.
4. Keep provider API tokens out of source control and CI logs. Prefer short-lived
   credentials or scoped tokens that can edit only the validation zone.
5. Validate public ACME issuance separately from default laptop mode.
6. Return to `BASE_DOMAIN=localhost` and Caddy internal certificates for normal
   development.

Tunnel providers such as ngrok or localtunnel can demonstrate reachability, but do
not use them as the default TLS validation path because they can terminate TLS
before Caddy and hide Caddy-owned certificate behavior.

## Laptop Troubleshooting

- If `.localhost` names fail, confirm the browser resolves them to loopback and no
  proxy/VPN rewrites local hostnames.
- If `laptop.sh validate` fails on ports, check for existing services bound to
  `127.0.0.1:80`, `127.0.0.1:443`, `127.0.0.1:4000`, or the FRPS ports.
- If `validate-tls` fails after config changes, restart the laptop stack or remove
  the laptop Caddy volume so cached local certificates do not mask changes.
- If FRPC validation fails, confirm `NIXSTASIS_FRPC_BINARY_PATH` points to a local
  `frpc` binary compatible with the server-side FRPS version.
- If browser terminal auth fails, rerun `laptop-client.sh prepare` before stack
  startup and verify `.laptop-client/authorized_keys` exists.
- On macOS, Docker Desktop and Apple Container differ in loopback and filesystem
  mount behavior; prefer Docker Compose for the laptop workflow until Apple
  Container behavior is explicitly validated.
- On Linux, ensure user permissions allow reading files under
  `deploy/compose/.laptop-client` and binding loopback ports below 1024 if running
  without Docker privileges.
- With Podman, verify Compose override tags such as `!override` and loopback port
  bindings render as expected before startup.

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
   The shipped example keeps placeholder digest-pinned image refs and secrets,
   so replace `NIXSTASIS_SERVER_IMAGE_REF`, `NIXSTASIS_CADDY_IMAGE_REF`,
   `NIXSTASIS_FRPS_IMAGE_REF`, and `POSTGRES_IMAGE_DIGEST` before validation.
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
- Run `deploy/compose/scripts/laptop.sh validate` to verify default laptop-mode
  templates and local environment wiring.
- Run `deploy/compose/scripts/laptop.sh validate-tls` after startup to verify
  local HTTPS and Caddy on-demand ask wiring.
- Run `deploy/compose/scripts/laptop-client.sh prepare` to verify local client
  template generation. Registration and FRPC polling require a running laptop
  stack and approval of the registered device in the UI.
- Run `NIXSTASIS_FRPC_BINARY_PATH=/path/to/frpc deploy/compose/scripts/laptop-client.sh validate-frpc`
  after startup to verify FRPC can connect to laptop FRPS.
- Run `deploy/compose/scripts/laptop-terminal-checklist.sh` to print the manual
  browser terminal checklist used during clean-state validation.

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
