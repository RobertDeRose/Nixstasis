# Server Provisioning

`Nixstasis.Provisioning` gives a freshly installed AtomixOS device its first configuration. An operator uploads one
artifact, and the server passes those exact bytes to AtomixOS over the device's `atomixos-bootstrap` FRP route. The
server never writes to the device's filesystem or unpacks the artifact; AtomixOS does all of that itself.

## Owns

- `Nixstasis.Provisioning` in `packages/server/lib/nixstasis/provisioning.ex`, with the artifact, HTTP client, and
  `Delivery` resource under `packages/server/lib/nixstasis/provisioning/`.
- Each delivery's record, its route lease, and its audit events.

## Entry points

The routes live under `/api/v1/provisioning`, behind Caddy and AuthCrunch operator sign-in. The operator needs
remote-access permission for the target device.

- `POST /devices/:device_id` uploads the artifact as an `application/octet-stream` body. The optional
  `x-config-filename` header names the file and defaults to `config.toml`. The optional
  `x-nixstasis-bootstrap-attempt-id` header, a UUID, marks a deliberate new attempt.
- `GET /deliveries/:id` shows a delivery's state, job progress, events, result, diagnostics, and audit identifiers. It
  never returns the artifact itself.
- `POST /deliveries/:id/withdraw` releases a route lease that was kept after an unclear outcome. It does not send the
  artifact again.

### How an upload runs

1. The server checks permission before reading the request body. The device must be approved and online.
2. It opens a lease with the `atomixos-bootstrap` profile. On its next heartbeat the device exposes its local
   `127.0.0.1:8080` HTTP service through that route, rewriting the `Host` header to `localhost`. The route itself is
   defined on the device, not by the server.
3. The server sends `HEAD /api/config` through the route until it gets a 2xx, or the 405 that endpoint normally
   returns. This gives the device time to pick up the lease, since heartbeats arrive every 30 seconds with the packaged config, or every 10 seconds when `poll.interval` is unset. Each
   probe times out after 30 seconds, and the server gives up after 60 seconds in total.
4. It posts the artifact and then polls the AtomixOS job until it finishes, as described below.

## Boundaries

### Each delivery holds its own lease

A delivery owns exactly one lease, recorded against its UUID in PostgreSQL. Withdrawing, resuming, polling, and
finishing all use that same lease, even after a server restart. Resuming never opens a new lease or extends the old
one; if the lease is gone or expired, the delivery stops. When a delivery finishes or is withdrawn, its credential
stops working, even if another operator still has access to the device.

Provisioning leases outrank browser leases, so an operator opening the device page cannot interrupt an upload. The full
precedence rules are in [Server Devices](server-devices.md).

### What the server accepts

The artifact must be non-empty and at most 32 MiB, with one of these filenames:

- `config.toml`
- `config-bundle.tar.gz` or `config-bundle.tgz`
- `config.tar.zst`, `config.tar.zstd`, or `config.tzst`

The server records the size and the lowercase SHA-256 digest, then sends the same bytes to `POST /api/config` with
`Content-Type: application/octet-stream` and `x-config-filename`. It sends no browser `Origin` or `Referer` header.
Checking the TOML or archive contents, and limiting decompression, is up to AtomixOS.

### Talking to AtomixOS

The server reaches AtomixOS at `https://atom-<normalized-device-uuid>-provisioning.<BASE_DOMAIN>`, the same host the
device's bootstrap route serves. `ATOMIXOS_PROVISIONING_BASE_URL` overrides it.

AtomixOS answers the upload with HTTP `202` and JSON containing a `job_id`, a job `state`, and a relative `job_url`
such as `/api/jobs/<job_id>`. The server only follows a job URL on the same host, with a short, URL-safe job ID.

The server then polls `GET /api/jobs/<job_id>` until the job finishes, for up to five minutes by default. The job
states are `submitted`, `running`, `succeeded`, and `failed`. The server keeps `current_step`, `events`, `error`,
`result`, and `rollback_status` when AtomixOS sends them.

Every response body is capped at 1 MiB. The server stops reading as soon as a body passes that size, before decoding or
saving anything. A `result.reapply: true` is not treated as success, because this is a first boot. `result.warnings`
and the older `result.forwarding_url` are kept for diagnosis only; the server never follows the forwarding URL.

### States and retries

The guiding rule is that the server never risks creating the same AtomixOS job twice.

| Delivery state          | Meaning                                                                   | Route lease                              |
|-------------------------|---------------------------------------------------------------------------|------------------------------------------|
| `submitting`            | The attempt is recorded, and the upload is not yet accepted.              | active                                   |
| `submitted` / `running` | AtomixOS accepted the job, and the server is polling it.                  | active                                   |
| `succeeded`             | The first boot finished and the result is recorded.                       | withdrawn                                |
| `failed`                | AtomixOS reported failure, or the request was rejected.                   | withdrawn                                |
| `indeterminate`         | A network error, a 5xx, or the polling deadline left the outcome unknown. | kept until withdrawn or until it expires |

- **Only a `409` is retried**, at most twice, with a growing delay. A `202` is never sent again.
- **An unclear upload becomes `indeterminate`.** That covers a network error, a 5xx, or an oversized `202` or 5xx
  response. A definite 4xx that is too large fails without the server reading the body.
- **Polling never re-uploads.** It only reads, within the deadline. A `404` while polling counts as a failure.
- **If the device never becomes reachable**, the delivery fails before anything is posted, and the lease is withdrawn.

Deliveries are identified by device, artifact SHA-256, and attempt ID. Asking again for an attempt that is still
running resumes polling its job, and asking again for a finished one returns the same result. After a failed or
`indeterminate` delivery, the operator has to check what happened on the device or start a new attempt with a new
attempt UUID. The server never quietly sends the same artifact again.

The server records the final result before withdrawing the lease. Withdrawing can safely be repeated, is audited, and
does not touch the AtomixOS job.

### Auditing

The server publishes structured events on `provisioning_audit`, through both Logger and PubSub, when an upload is
rejected, starts, succeeds, fails, or ends up `indeterminate`, and when a lease is withdrawn. Each event names the
operator, device, attempt, artifact digest, delivery state, job ID, and a short error message. The delivery record
keeps the progress and rollback details operators need to work out what happened.

The request and response shapes are in the Device API under [OpenAPI Contracts](../reference/openapi/index.md). The FRP
route that carries the artifact is described in [Gateway FRP](gateway-frp.md).
