# Packaging and Deployment Migration

There is now one supported way to deploy the server, with Docker Compose, and one way to release the client, with
GoReleaser. Client releases include `frpc`, configuration templates, and systemd files, with pinned runtime versions
and release checks. The original plan is in the [design record](design.md).

## What changed for users

- **Operators** deploy Phoenix, Caddy with AuthCrunch, FRPS, and PostgreSQL from `deploy/compose`.
- **Device administrators** install a native package or a self-extracting installer, and no longer need to install
  `frpc` separately.

## How it fits in

Compose defines the server's services and how they are configured. GoReleaser, with a shared FRP download step, builds
the client packages. Database migrations stay a separate step from starting the server.

## Running it

Validation scripts catch missing settings, unsafe port exposure, mismatched images, and packaging problems before a
release or deployment.

## Differences from the design

Self-extracting installers were added to the release, and the tooling was brought together under mise.

## Not included

- The old server packaging is no longer supported.
- There is only one supported server deployment.

## Tests

- `deploy/compose/scripts/validate_stack.sh`, tested by `deploy/compose/scripts/test_validate_stack.py`: Compose
  rendering, required server settings, and port exposure.
- `deploy/compose/scripts/check_frps_config.sh` and `deploy/compose/scripts/check_proxy_claims.py`: the FRPS and proxy
  configuration.
- `packages/server/test/nixstasis_web/runtime_contract_test.exs`: the settings the server expects at runtime.
- `packages/client/build/bin/verify_artifacts.sh`: client binaries, the bundled `frpc`, templates, systemd units,
  versions, and installers.

## Related pages

- [Deployment](../../operations/deployment.md)
- [Client Installation](../../operations/client-installation.md)
- [Deployment Configuration](../../reference/deployment-configuration.md)
- `deploy/compose/README.md`
- `packages/client/README.md`
