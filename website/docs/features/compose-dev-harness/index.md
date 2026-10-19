# Compose Dev Harness

A development lab that runs the whole stack on a laptop with one command: Phoenix, PostgreSQL, Caddy, FRPS, and
simulated devices. With it you can test local TLS routing, device registration and polling, FRP tunnels, and browser
terminals without public DNS. The original plan is in the [design record](design.md).

## What changed for users

- `mise run deploy:dev -- up --clients N` starts the lab with `N` simulated devices.
- Local hostnames mirror production: `nixstasis.localhost`, `auth.localhost`, `frp-admin.localhost`, and a wildcard
  name for each device.
- Caddy uses local certificates, but still asks Phoenix before issuing one, just as in production.
- Testing against public DNS is optional, and kept separate from the default workflow.

## How it fits in

The lab runs the same `deploy/compose` setup as production, not a separate one. Phoenix stays behind Caddy, `frpc`
connects to FRPS, and each simulated device runs systemd, sshd, and the packaged client.

## Running it

Development settings and credentials come from tracked development defaults and from runtime files Git ignores, so
they never mix with production. Production Compose setup and public certificates are documented separately from the
laptop lab.

## Differences from the design

The lab is driven by mise tasks, while Compose still runs the services.

## Not included

- Public DNS and ACME are not part of the default workflow; testing them is an optional, manual check.
- The lab needs no hosted staging environment, tunnel provider, or public DNS, and does no load testing.

## Tests

- `deploy/compose/scripts/test_validate_stack.py` and `deploy/compose/scripts/validate_stack.sh`: Compose stack
  validation.
- `packages/server/test/nixstasis_web/controllers/tls_controller_test.exs`: Caddy's certificate check against Phoenix.
- `packages/server/test/nixstasis_web/channels/terminal_channel_test.exs` and
  `packages/server/test/nixstasis_web/live/device_live_test.exs`: the browser terminal from start to finish.
- Manual lab check: `mise run deploy:dev -- up --clients N` starts simulated devices that register and poll, and the UI
  is reachable on the local TLS hostnames.

## Related pages

- [Local Stack](../../development/local-stack.md)
- [Development](../../development.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
- [Deployment](../../operations/deployment.md)
