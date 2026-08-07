# AtomixOS Bootstrap Provisioning

## Delivery Summary

- Beads task: `nixstasis-4gg`
- Status: delivered
- Dependencies: `nixstasis-255`, `nixstasis-fss`
- Pull request: none authorized or created

## Delivered Capability

An authorized operator can deliver one complete initial AtomixOS
`config.toml` or approved config bundle to an approved, online device. The
server opens the client-owned `atomixos-bootstrap` FRP route, posts the opaque
artifact to AtomixOS `/api/config`, polls its job, records the result, and
withdraws the route lease after terminal completion.

The implementation deliberately does not write the device filesystem, unpack
archives, use the browser-only `/apply` flow, or retry an accepted upload.

## User-Facing Behavior

- Uploads use `POST /api/v1/provisioning/devices/:device_id` with exact
  `application/octet-stream` bytes.
- Operators can inspect delivery progress and diagnostics with
  `GET /api/v1/provisioning/deliveries/:id`.
- Operators can withdraw a retained indeterminate route lease with
  `POST /api/v1/provisioning/deliveries/:id/withdraw`.
- Unauthorized, unapproved, offline, invalid, missing-route, failed, expired,
  and unknown-outcome cases fail closed without a silent duplicate upload.

## Design Integration

The action reuses device authorization, online checks, remote-access leases,
Caddy wildcard routing, the versioned client-owned FRP profile, and structured
Logger/PubSub audit conventions. The server selects only the named
`atomixos-bootstrap` profile; the client owns its target, HTTP mode, and fixed
local Host rewrite.

## Operational Impact

Artifacts are limited to 32 MiB and tracked by lower-case SHA-256. Accepted
and polled JSON payloads are bounded to 1 MiB before durable persistence. The
default job-poll deadline is five minutes, request timeout is 30 seconds, and only HTTP
409 submission conflicts receive two bounded retries. Ambiguous uploads become
indeterminate and retain access until explicit withdrawal or lease expiry.
`ATOMIXOS_PROVISIONING_BASE_URL` can override the derived per-device FRP base;
`BASE_DOMAIN` remains the default host derivation input.

## Reference and Contracts

- [Server Provisioning](../../modules/server-provisioning.md)
- [Client-server interface](../../client-server-interface.md)
- [Device API OpenAPI](../../reference/openapi/device-api.yaml)
- [Edge FRP](../../modules/edge-frp.md)
- [Compose deployment](../../modules/deployment-compose.md)

## Validation Evidence

Focused server tests cover artifact limits, authorization and approval gates,
route submission, job polling, success, queue-conflict retry, ambiguous upload,
lease expiry, indeterminate reconciliation, and withdrawal:

```bash
cd packages/server
mise x -- mix test \
  test/nixstasis/provisioning/artifact_test.exs \
  test/nixstasis/provisioning_test.exs \
  test/nixstasis_web/controllers/provisioning_controller_test.exs
```

The final repository validation evidence is recorded with Beads task
`nixstasis-4gg` and the implementation commit.

## Design Reconciliation

### Delivered as Designed

The server action uses the existing authorized FRP path, the documented
AtomixOS `/api/config` and job API, bounded retries/polling, durable state,
audit events, idempotency, and explicit one-time lease withdrawal.

### Intentional Changes

The durable delivery resource adds an operator-facing status surface and
retains the latest job events/result because AtomixOS reports progress through
the job resource rather than through a second Nixstasis command protocol.

### Deferred Work

Human measurement of the broader 90-second usability target remains deferred;
this task has no human observation evidence. AtomixOS post-provision re-apply
remains outside this initial-bootstrap action.

### Rejected or Removed Scope

No direct filesystem writer, archive extractor, browser `/apply` endpoint,
client-supplied route definition, arbitrary Host rewrite, automatic duplicate
POST, or forwarding-URL follow behavior was added.

## Documentation Updated

- `docs/src/features/atomixos-bootstrap-provisioning/design.md`
- `docs/src/modules/server-provisioning.md`
- `docs/src/client-server-interface.md`
- `docs/src/modules/server-devices.md`
- `docs/src/modules/edge-frp.md`
- `docs/src/reference/contracts.md`
- `docs/src/reference/openapi/device-api.yaml`
- `deploy/compose/README.md`

## Audit Trail

The implementation is tracked by Beads issue `nixstasis-4gg`. Review and
validation limitations are recorded in its notes; no independent Pi reviewer
session was available. No push or pull request was authorized or performed.
