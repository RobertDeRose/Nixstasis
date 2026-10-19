# Local Stack

The development lab runs the same Compose stack as production on a laptop, with real device simulators, so Caddy TLS
approval, FRP tunnels, PCP telemetry, and browser SSH terminals can be exercised end to end. It uses the single
`deploy/compose/docker-compose.yml` with the tracked `deploy/compose/dev.env`.

## Run it

```sh
mise run deploy:dev -- up --clients 2
```

`up` builds the images locally with `dev` tags, starts the stack, runs migrations, starts the requested number of
`client` simulators, and pre-approves them so their retrying registration receives a runtime token. Other commands:

| Command                                  | Effect                                                                                                                                                                                               |
|------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `mise run deploy:dev:seed`               | Adds idempotent fixture data: schema-builder devices, versions, telemetry, an alert, and a report. These database-only devices stay offline and have no FRP routes; use a simulator for SSH testing. |
| `mise run deploy:dev -- client-logs`     | Shows client logs from journald inside the simulators.                                                                                                                                               |
| `mise run deploy:dev -- logs -f client1` | Follows one simulator's container logs.                                                                                                                                                              |
| `mise run deploy:dev -- down`            | Removes the containers and named volumes, including the database, so the next `up` starts empty.                                                                                                     |

## How it differs from production

- **Hostnames:** `BASE_DOMAIN=localhost`, so the hosts are `nixstasis.localhost`, `auth.localhost`,
  `frp-admin.localhost`, and `atom-<normalized-device-id>.localhost`.
- **Certificates:** Caddy issues its own local certificates. The task copies only Caddy's public local CA into each
  simulator's trust store; certificate and hostname checks stay on.
- **Sign-in:** `Caddyfile.dev` binds to loopback and uses Phoenix's local operator fallback instead of a live identity
  provider. `Caddyfile.laptop` tests real AuthCrunch with OIDC credentials.
- **Cookies:** the dev image is built with `NIXSTASIS_SESSION_COOKIE_SECURE=false` for the loopback HTTP UI.
- **Simulators:** each `client` runs Ubuntu with systemd as PID 1, `sshd`, `frpc`, PCP, and the client.
  `nixstasis-simulator-http.service` serves HTTPS on `127.0.0.1:443` so device HTTP routes can be tested through Caddy,
  FRPS, and `frpc`. Because the poll service cannot reach the system manager inside the container, `frpc` runs through
  the hidden `frp-session` command. `systemd-user-sessions.service` stays enabled so `nixstasis-support` can log in over
  SSH.
- **Public-fidelity testing:** to exercise public ACME, point `BASE_DOMAIN` at DuckDNS or a domain you own.

## Contract validation

`mise run check` and the pre-commit hook run the first two whenever their files change. The Caddy and FRPS checks run in
their image workflows; run them by hand after changing a Caddyfile or `frps.toml`.

- Stack validation, for changes under `deploy/compose/`:

  ```sh
  python3 deploy/compose/scripts/test_validate_stack.py
  ```

- The FRPS config renderer, for changes under `packages/frp/` or `deploy/compose/frps/`:

  ```sh
  uv run packages/frp/bin/test_frps_render_config.py
  ```

- Caddy's claim and header rules, run against the repository-built Caddy image in a disposable container that needs
  no host Caddy or Python:

  ```sh
  mise run deploy:dev -- build caddy
  mise run deploy:dev -- run --rm --no-deps \
    --entrypoint /bin/sh \
    --volume "$PWD:/workspace:ro" \
    --workdir /workspace \
    caddy -c 'apk add --no-cache python3 &&
      python3 deploy/compose/scripts/check_proxy_claims.py --caddy /usr/bin/caddy'
  ```

  The checks use loopback HTTP, signed test tokens, and an echo upstream; TLS, OIDC sign-in, and full WebSocket
  handshakes are out of scope. The Caddy image workflow runs them before publishing.

- The FRPS config, verified with the pinned `frps` binary:

  ```sh
  mise run deploy:dev -- build frps
  deploy/compose/scripts/check_frps_config.sh nixstasis-frps:dev
  ```

  This catches structural mistakes, such as a top-level key after a `[[httpPlugins]]` table. The FRPS image workflow
  runs the same check and publishes only the image it verified.
