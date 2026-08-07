# Design — AtomixOS Bootstrap Provisioning

## Metadata

- Beads task: `nixstasis-4gg`
- Feature slug: `atomixos-bootstrap-provisioning`
- Design path: `docs/src/features/atomixos-bootstrap-provisioning/design.md`
- Implemented record: `docs/src/features/atomixos-bootstrap-provisioning/index.md`
- Base branch: `dev`
- Status: delivered

## Feature Summary

Deliver one complete initial AtomixOS desired-state artifact through the
existing authorized `atomixos-bootstrap` FRP route. Nixstasis owns operator
authorization, bounded transport, durable delivery state, job polling, audit
events, idempotency, and route-lease withdrawal. AtomixOS owns archive/TOML
validation and device mutation.

## User Intent

An authorized operator needs a safe server action for first-boot fleet
provisioning without direct filesystem access, browser-only CSRF flows, or a
second device mutation protocol. A transport failure must not silently create
a duplicate provisioning job, and an operator must be able to reconcile an
unknown result and withdraw temporary access.

## Goals

- Require an approved, online device and trusted remote-access permission.
- Select the client-owned `atomixos-bootstrap` profile and open a lease before
  any upload.
- Send exact bounded `application/octet-stream` bytes to AtomixOS `/api/config`.
- Poll the documented job resource with bounded timeouts and retries.
- Persist digest, job progress, result, failure, rollback diagnostics, and
  lease state.
- Make terminal results idempotent and require an explicit new attempt before
  any retry after a failed or unknown delivery.
- Withdraw the one-time route lease after a terminal result and expose
  structured audit events.

## Non-Goals

- Writing `/data/config` or any other device filesystem from Phoenix.
- Unpacking, validating, signing, or mutating an artifact locally.
- Re-applying an already provisioned device.
- Following AtomixOS `forwarding_url` or using browser `/apply` and CSRF.
- Accepting client-supplied FRP targets, route definitions, credentials, or
  arbitrary Host-header values.

## User-Facing Behavior

- `POST /api/v1/provisioning/devices/:device_id` accepts one raw artifact with
  the exact `application/octet-stream` content type.
- `GET /api/v1/provisioning/deliveries/:id` returns progress without artifact
  bytes.
- `POST /api/v1/provisioning/deliveries/:id/withdraw` withdraws a retained
  indeterminate route lease without uploading another artifact.
- Authorization, approval, offline, malformed artifact, missing route,
  rejected submission, failed job, expired lease, and unknown outcome paths
  fail closed and emit structured audit events.

## Requirements

### Functional Requirements

- The AtomixOS request is `POST /api/config` with exact bytes and optional
  `x-config-filename`; accepted responses provide `job_id`, `state`, and a
  relative `/api/jobs/<job_id>` URL.
- Polling accepts `submitted`, `running`, `succeeded`, and `failed`; events,
  current step, error, result, and rollback status are retained.
- Only HTTP 409 submission conflicts retry, with at most two retries. Accepted
  202 responses, ambiguous upload errors, and polling failures never trigger a
  duplicate POST.
- The upload limit is 32 MiB. Artifact identity is lower-case SHA-256 plus
  device and bootstrap-attempt UUID.
- Successful and failed terminal results are recorded before route withdrawal;
  indeterminate results retain access until explicit withdrawal or expiry.

### Quality and Security Requirements

- Check operator authorization before reading the upload body.
- Resolve only the documented relative job path against the authorized FRP API
  base and reject unsafe job identifiers or mismatched job IDs.
- Never return artifact bytes or follow `forwarding_url`.
- Attribute audit events to the trusted operator subject and bound diagnostic
  text and payloads to durable, non-secret fields.
- Preserve the existing server/client FRP ownership boundary: the server sends
  only the named profile reference, while the client owns route details and
  the fixed local Host rewrite.

## Architecture Consistency

The server action is a retained Phoenix controller boundary backed by an Ash
resource. It delegates device authorization and lease lifecycle to
`Nixstasis.Devices`, profile selection to the existing remote-access contract,
HTTP transport to a small Req adapter, and audit emission to the same
Logger/PubSub pattern used by scripts and device groups. The client remains
the route-definition authority.

## Operational Considerations

The default compressed/plain upload limit is 32 MiB, request timeout is 30
seconds, polling deadline is five minutes, and route leases use the existing
one-hour lease default. Operators must retain the public wildcard FRP/Caddy
route and AtomixOS API base. `ATOMIXOS_PROVISIONING_BASE_URL` is an optional
runtime override; otherwise `BASE_DOMAIN` derives the per-device host.

## Documentation Impact

The operator and integration contract is maintained in
`docs/src/modules/server-provisioning.md`, `docs/src/client-server-interface.md`,
and `docs/src/reference/openapi/device-api.yaml`. FRP ownership is described
in `docs/src/modules/edge-frp.md`, and deployment configuration is described in
`deploy/compose/README.md`.

## Validation Strategy

Write behavior tests for artifact validation, authorization ordering, route
selection, accepted response normalization, terminal job states, 409 retry,
ambiguous transport, polling deadlines, lease expiry, idempotency, and
withdrawal. Run focused tests during implementation, then Ash code generation
checks, server precommit, documentation checks, and repository diff checks.

## Implementation Decomposition

1. Add the bounded artifact value object and durable delivery resource/migration.
2. Add the provisioning orchestration, Req adapter, lease lifecycle, polling,
   idempotency, and audit events.
3. Register the domain resource, supervisor, and operator controller routes.
4. Add controller/resource tests and reconcile the operator, FRP, deployment,
   and OpenAPI documentation.

## Dependencies and Parallelism

This work depends on `nixstasis-255` for named/versioned profile selection and
`nixstasis-fss` for the fixed local Host rewrite. The server implementation,
resource migration, controller contract, and documentation are coupled and
should land together. No independent parallel implementation is safe because
all steps share the lease and duplicate-submission boundary.

## Risks and Tradeoffs

- A synchronous bounded GenServer call keeps lease ownership in one process
  but serializes provisioning attempts; this favors correctness and explicit
  cleanup over throughput for the initial action.
- An ambiguous POST is kept indeterminate instead of guessed successful or
  retried, preventing duplicate first-boot jobs at the cost of operator
  reconciliation.
- Job payloads are retained for useful diagnostics but artifact bytes are not,
  limiting durable storage and secret exposure.
- Lease expiry is treated as unknown after an accepted upload and as a failed
  pre-upload action, preserving fail-closed behavior in both cases.

## Open Questions

- Human observation of the broader 90-second operator usability target is not
  available and remains deferred.
- AtomixOS post-provision re-apply is intentionally outside this initial-boot
  contract and requires a separate approved API design.

## Existing Context

The FRP route-profile contract is implemented by `nixstasis-255` and the
`nixstasis-fss` follow-up. Device authorization, online status, lease ownership,
heartbeat profile references, Caddy wildcard authorization, and Logger/PubSub
audit conventions already exist.

Relevant paths:

- `packages/server/lib/nixstasis/devices.ex`
- `packages/server/lib/nixstasis/devices/device.ex`
- `packages/server/lib/nixstasis/provisioning.ex`
- `packages/server/lib/nixstasis_web/controllers/provisioning_controller.ex`
- `packages/client/internal/config/route_profile.go`
- `packages/client/internal/frp/render.go`
- `deploy/compose/caddy/Caddyfile`

## Proposed Design

1. Validate authorization, device state, filename, size, digest, and attempt
   identity before creating a durable delivery record.
2. Open a server-owned remote-access lease using `atomixos-bootstrap`, derive
   the per-device HTTPS FRP base, and post the opaque bytes through the route.
3. Persist the accepted job identity and resolve only its relative job path.
4. Poll until terminal completion or a five-minute default deadline. Record each
   latest job payload and translate terminal state into the delivery state.
5. Withdraw access after success or failure. Keep indeterminate state explicit;
   allow reconciliation reads and one-time withdrawal, but never silently
   repost the same bytes.
6. Emit structured audit events at rejection, start, terminal outcome, lease
   expiry, and explicit withdrawal boundaries.

## State Model

- `submitting`: durable record exists before AtomixOS accepts a request.
- `submitted` / `running`: an accepted job is being polled while the lease is
  active.
- `succeeded`: initial bootstrap succeeded and access is withdrawn.
- `failed`: AtomixOS or transport rejected the request/job and access is
  withdrawn.
- `indeterminate`: the accepted outcome cannot be proven; access remains until
  explicit withdrawal or expiry.

## Documentation and Validation Impact

The operator contract is defined in `docs/src/modules/server-provisioning.md`,
`docs/src/client-server-interface.md`, and the maintained device OpenAPI file.
The FRP and deployment docs identify the profile, Host rewrite, base URL
override, and lease boundary. Server tests cover artifact validation,
authorization, approval, routing, polling, success, failure, conflict retry,
lease expiry, indeterminate reconciliation, and withdrawal.
