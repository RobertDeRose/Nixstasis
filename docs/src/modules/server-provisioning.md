# Server Provisioning

## Purpose

`Nixstasis.Provisioning` delivers one complete initial AtomixOS desired-state
artifact through the device's authorized `atomixos-bootstrap` FRP route. The
server sends opaque bytes to AtomixOS; it never writes the device filesystem,
unpacks an archive, or introduces a second mutation protocol.

## Operator API

The controller routes are under `/api/v1/provisioning` and use the trusted
Caddy/AuthCrunch operator boundary. The operator must have remote-access
permission for the target device.

- `POST /devices/:device_id`: upload an exact
  `application/octet-stream` body. The optional `x-config-filename` header
  defaults to `config.toml`; the optional
  `x-nixstasis-bootstrap-attempt-id` UUID identifies an explicit attempt.
- `GET /deliveries/:id`: read delivery state, job progress, events, result,
  diagnostics, and audit identifiers. Artifact bytes are never returned.
- `POST /deliveries/:id/withdraw`: withdraw a retained route lease after an
  indeterminate outcome. Withdrawal does not submit another artifact.

The upload is authorized before the request body is read. The target must be
approved and online. The action then opens a lease using the named
`atomixos-bootstrap` profile, which causes the client to expose its local
`127.0.0.1:8080` HTTP service with the fixed downstream `Host: localhost`
rewrite. Route definitions and header values remain client-owned.

Before sending the artifact, the server performs a read-only `HEAD /api/config`
probe through the same route. An HTTP 2xx response or the endpoint's expected
405 method-not-allowed response proves that the device route is reachable;
other statuses and transport errors are retried with a bounded 60-second
readiness deadline, 30-second request timeout, and backoff. This
preflight gives the client time to receive the lease on its next heartbeat,
whose default interval is 30 seconds.

## Artifact boundary

The server accepts non-empty opaque artifacts no larger than 32 MiB. Accepted
filenames are:

- `config.toml`
- `config-bundle.tar.gz` or `config-bundle.tgz`
- `config.tar.zst`, `config.tar.zstd`, or `config.tzst`

The server records the byte count and lower-case SHA-256 digest, then sends the
same bytes to `POST /api/config` with `Content-Type: application/octet-stream`
and `x-config-filename`. It sends no browser `Origin` or `Referer` header.
AtomixOS owns TOML/archive validation and decompression limits.

## AtomixOS job contract

The FRP API base is derived from the device identity as
`https://atom-<normalized-mac>.<BASE_DOMAIN>`, or can be explicitly set with
`ATOMIXOS_PROVISIONING_BASE_URL`. The server posts to `/api/config` and accepts
HTTP `202` JSON containing `job_id`, a documented job `state`, and a relative
`job_url` such as `/api/jobs/<job_id>`. The job URL must stay on the same FRP
API base and the job identifier must be a bounded URL-safe segment.

The server polls `GET /api/jobs/<job_id>` until a terminal state or the bounded
five-minute default deadline. Documented states are `submitted`, `running`,
`succeeded`, and `failed`; `current_step`, `events`, `error`, `result`, and
`rollback_status` are retained when present. The accepted response and each
job payload are bounded to 1 MiB before durable persistence. `result.reapply:
true` is not a valid initial bootstrap success. `result.warnings` and legacy
`result.forwarding_url` are diagnostic; the forwarding URL is never followed.

## State, retries, and idempotency

| Delivery state          | Meaning                                                                | Route lease                                  |
|-------------------------|------------------------------------------------------------------------|----------------------------------------------|
| `submitting`            | Durable attempt exists before a response is accepted.                  | active                                       |
| `submitted` / `running` | AtomixOS accepted the job and polling is active.                       | active                                       |
| `succeeded`             | Initial bootstrap completed and the result was recorded.               | withdrawn                                    |
| `failed`                | AtomixOS returned a terminal failure or the request was rejected.      | withdrawn                                    |
| `indeterminate`         | A transport/5xx response or polling deadline left the outcome unknown. | retained until explicit withdrawal or expiry |

Only HTTP `409` responses are retried, with at most two bounded retries and
linear backoff. A `202` is never submitted again. An ambiguous upload transport
error or 5xx becomes `indeterminate`; the server does not risk creating a
duplicate AtomixOS job. Polling is read-only and bounded by the action deadline;
a polling `404` is a failure, not a reason to upload again.

Delivery records are keyed by device, artifact SHA-256, and bootstrap-attempt
identity. Re-entering an active attempt polls its known job. A terminal result
is returned idempotently. An indeterminate or failed delivery requires
reconciliation or an explicit new attempt UUID; the same artifact is never
silently reposted.

A readiness timeout fails the delivery before `POST /api/config`, withdraws
the lease, and records a clear failure. Once the POST begins, the existing
no-duplicate rules apply: ambiguous upload outcomes remain indeterminate and
are never automatically reposted.

The action records the terminal result before withdrawing the lease. Lease
withdrawal is idempotent, audited, and does not alter the AtomixOS job.

## Auditing and observability

Provisioning emits structured Logger/PubSub events on `provisioning_audit` for
rejection, start, success, failure, indeterminate outcome, and explicit lease
withdrawal. Events include the trusted operator, device, attempt, artifact
digest, delivery state, job identifier, and bounded error text. The durable
delivery record retains progress and rollback diagnostics for operator
reconciliation.

## Implementation references

- `packages/server/lib/nixstasis/provisioning.ex`
- `packages/server/lib/nixstasis/provisioning/artifact.ex`
- `packages/server/lib/nixstasis/provisioning/http_client.ex`
- `packages/server/lib/nixstasis/provisioning/delivery.ex`
- `packages/server/lib/nixstasis_web/controllers/provisioning_controller.ex`
- `docs/src/reference/openapi/device-api.yaml`
- [Edge FRP](edge-frp.md)
- [Client-server interface](../client-server-interface.md)
