# Compose Dev Harness

## Delivery Summary

- Beads feature root: `nixstasis-ed8`
- Status: delivered
- Pull request: not recorded in the legacy workflow
- Delivery commit: `6deea930afdb70641c28ecf5a179037d9c9d510f`
- Design record: `design.md`

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

## Validation Evidence

Legacy delivery evidence records runtime-contract checks, Compose stack validation, local TLS approval checks, managed
client registration and polling, and LiveView terminal lifecycle coverage. The implementation is corroborated by
`deploy/compose/README.md`, `deploy/compose/scripts/check_runtime_contract.sh`, and server terminal tests.

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

## Audit Trail

Legacy tasks were imported beneath `nixstasis-ed8`. Commit `6deea930afdb70641c28ecf5a179037d9c9d510f` moved the
dev-lab entry point to mise and directly updated the corroborating deployment documentation.
