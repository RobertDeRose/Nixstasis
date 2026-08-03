# Stary Script Workbench

## Purpose

The Stary Script Workbench lets an authorized operator create, validate, test, and deploy
`.stary` telemetry scripts from the Phoenix web UI. It complements the client-local Stary
CLI; it does not replace the Go client's parser, runtime, or execution safeguards.

Open the inventory at `/scripts`, then open a draft at `/scripts/:id`.

## Authorization and target scope

Script authoring, validation, testing, deployment, retry, cancellation, and archive actions
are operator mutations. Production browser access is admitted by Caddy/AuthCrunch and mapped
from trusted `X-Token-*` claims into the Phoenix session.

- The `Nixstasis.Scripts` context is the authorization boundary.
- Test and deployment targets are checked against the trusted device scope before a run or
  pending command is created.
- An unscoped operator may target approved devices visible to the operator.
- A scoped operator may target only the listed device IDs; empty or mixed selections fail
  without creating partial runs or commands.
- LiveView device filtering improves presentation but is not the security control.
- Missing trusted actor context fails closed for operator mutations in production. Audit
  events use the trusted subject, falling back to the trusted email when needed.

Device API tokens authenticate result ingestion separately. A device result is attributed to
the authenticated device, not to the browser operator who queued the run.

## Authoring workflow

1. Create a draft from the Scripts inventory.
2. Edit structured front matter and the Starlark body.
3. Validate the rendered `.stary` artifact.
4. Select one or more authorized devices on the **Test** tab.
5. Queue a test and inspect per-client status and result payloads.
6. Deploy only a validated version after the UI's test gate has passed.
7. Use retry for failed or partial runs, or cancel active server-side runs when required.

The server stores draft front matter and body separately, then renders the canonical
artifact. A version's `rendered_content` is immutable for the purposes of validation, test,
and deployment, so editing a draft cannot change an already queued artifact.

## Validation boundary

`Nixstasis.Scripts.Validator` performs bounded server preflight:

- required front matter and non-empty script name;
- schema shape checks;
- non-empty body and conservative Starlark structure checks; and
- canonical `.stary` rendering.

The Go client remains authoritative for complete Stary parsing, schema compilation, builtins,
command allowlisting, timeouts, runtime errors, and output validation. A server preflight
failure prevents queueing. A client-side validation or runtime failure is recorded as a
normal per-client result.

## Test and deployment behavior

Testing queues a `run_script` device command. The client executes the supplied content with
its normal Go runtime and does not install the content into the polling script directory.
Deployment queues `install_script` for a validated version and uses the same client-side
front matter, version, schema, and filesystem safeguards as any other install.

Small payloads are delivered inline. When the rendered content exceeds the server's
4,096-byte inline threshold, the command keeps a `payload_ref` and marks the payload as
deferred. The client poll loop fetches the payload through the authenticated compatibility
endpoint before invoking the command handler:

```text
GET /api/v1/devices/:device_id/command_payloads/:ref?api_key=...
```

A missing or invalid deferred payload produces a failed command result and a failed
per-client action; it never executes or installs the incomplete content. Existing
`/api/v1` heartbeat, command-result, and payload-fetch contracts remain in use.

## Run states and recovery

The workbench records separate state for drafts, versions, validation runs, test runs,
deployment runs, and per-client actions. The important run states are:

- Test: `pending`, `running`, `passed`, `failed`, `timed_out`, `unsupported`, `unavailable`.
- Deployment: `pending`, `running`, `deployed`, `partial`, `failed`.
- Client action: `queued`, `delivered`, `acknowledged`, `failed`, `missing_payload`.

Commands are delivered during the device heartbeat. Offline devices remain pending until
they poll. A server cancellation marks the run failed; a command already delivered to a
client may still finish and report independently. Retry targets the original run's devices
that remain authorized and visible to the operator.

## Audit and retention

Successful operator mutations and validation failures emit structured script audit events
with `action`, `actor_id`, `actor_type: :operator`, UTC `timestamp`, and relevant script,
version, target, or result fields. Device-originated result events use
`actor_type: :device` and the authenticated device ID.

`Nixstasis.Scripts.Audit` writes each event to the Elixir `Logger` and broadcasts
`{:script_audit, payload}` on the `script_audit` PubSub topic. There is no separate audit
table. Durable retention, export, and access control therefore follow the deployment's
structured-log collection policy; PubSub is an in-process notification mechanism only.

## Troubleshooting

- **Not authorized:** confirm the browser role and, for a scoped operator, the target device
  claim. Reopen the page after the trusted session changes.
- **No script version available:** validate the draft and ensure the front matter includes a
  non-empty version.
- **Test or deployment remains pending:** inspect the device's last heartbeat and command
  delivery state. The server waits for the device to poll.
- **Missing payload:** inspect the per-client action and server structured logs for the
  payload reference. The client reports a deterministic payload-fetch failure.
- **Client validation or execution failure:** use the per-client result payload. Correct
  the script, schema, runtime assumptions, or device command policy, then retry.

## Contract boundary

The six `script_*` Ash resources are internal persistence records. They are intentionally
not exposed as generic Ash JSON:API CRUD resources. The current UI calls the domain through
`Nixstasis.Scripts` and `Nixstasis.Domain`, preserving validation, target authorization,
command dispatch, and audit boundaries.

See [Server Scripts](../modules/server-scripts.md) for the architecture and
[Client-Server Interface](../client-server-interface.md) for the device command contract.
