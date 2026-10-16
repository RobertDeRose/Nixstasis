# Compose Dev Harness

## References

- Beads feature root: `nixstasis-ed8`
- Design record: [design.md](design.md)

## Delivered Capability

Nixstasis provides a Compose-based development lab that starts the Phoenix control plane, PostgreSQL, Caddy, FRPS,
and managed client simulators through one deployment-shaped workflow. Developers can validate local TLS routing,
device registration and polling, FRP connectivity, and browser terminal behavior without requiring public DNS.

## User-Facing Behavior

- `mise run deploy:dev -- up --clients N` starts the local lab with managed client containers.
- Local hosts mirror production routing through `nixstasis.localhost`, `auth.localhost`, `frp-admin.localhost`, and
  device wildcard names.
- Caddy uses local certificates while retaining the Phoenix domain-approval boundary.
- Optional public-fidelity guidance remains separate from the default local workflow.

## Design Integration

The harness reuses the supported `deploy/compose` topology rather than introducing a second runtime architecture.
Phoenix remains behind Caddy, FRPC reaches FRPS, and simulated clients run systemd, sshd, and the packaged Go client.

## Operational Impact

Development state and credentials are isolated to tracked development defaults and ignored runtime files. Production
Compose guidance and public certificate behavior remain distinct from laptop validation.

## Reference and Contracts

- [Development](../../development.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
- [Deployment Compose](../../modules/deployment-compose.md)
- `deploy/compose/README.md`

## Test Coverage

- `deploy/compose/scripts/test_validate_stack.py` and `deploy/compose/scripts/validate_stack.sh`: Compose stack
  validation.
- `packages/server/test/nixstasis_web/controllers/tls_controller_test.exs`: Caddy domain-approval (TLS ask) boundary.
- `packages/server/test/nixstasis_web/channels/terminal_channel_test.exs` and
  `packages/server/test/nixstasis_web/live/device_live_test.exs`: browser terminal lifecycle.
- Manual dev-lab check: `mise run deploy:dev -- up --clients N` starts managed client simulators that register and
  poll, and the server UI is reachable through local TLS hostnames.

## Design Reconciliation

### Delivered as Designed

The one-command local lab, deployment-shaped service boundaries, local hostname scheme, and managed client simulator
were delivered.

### Intentional Changes

The final workflow moved dev-lab orchestration into mise tasks while retaining Compose as the runtime authority.

### Deferred Work

Public DNS and ACME validation remain optional operator-led fidelity checks.

### Rejected or Removed Scope

The default workflow does not require a hosted staging environment, tunnel provider, load testing, or public DNS.

## Documentation Updated

- `docs/src/development.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/modules/deployment-compose.md`
- `deploy/compose/README.md`
