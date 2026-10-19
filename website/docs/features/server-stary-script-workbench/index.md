# Server Stary Script Workbench

Operators can write and edit Stary scripts in the web UI, validate them, test them on chosen devices, read each
device's result, and deploy a validated version, all through the normal authenticated device commands. The server keeps
drafts, fixed versions, validation runs, test and deployment runs, and each device's part in a run, but offers no
JSON:API routes for editing scripts directly. The original plan is in the [design record](design.md).

## What changed for users

- `/scripts` lists drafts, and `/scripts/:id` has the editor and the run history.
- Validation checks the front matter, the schema, and the basic Starlark structure before anything is queued.
- A test sends `run_script`, which runs the script without installing it.
- A deployment sends `install_script` with the fixed, rendered version (`ScriptVersion.rendered_content`).
- Chosen devices are checked against your access on the server. If the list is empty, or includes a device you
  cannot access, nothing is created.
- Active and failed runs can be retried or cancelled, and devices that have not checked in yet show as pending.
- Audit events name the operator. Results are credited to the device that reported them.

How to use it day to day is covered in [Stary Script Workbench](../../operations/script-workbench.md).

## How it fits in

Phoenix handles writing scripts, the quick validation, storing workbench state, checking targets, audit events, and
coordinating runs. `Nixstasis.Devices` and `Nixstasis.Monitoring` still authenticate devices, own the command queue,
deliver commands with heartbeats, and carry results back. The client still has the final say on parsing, builtins,
command policy, timeouts, output checks, and running the script.

Large scripts use the existing deferred payload flow: the server keeps the script, and the client's poll loop fetches it
before running the command. Devices still use the `/api/v1` protocol.

## Running it

Script commands reach devices with their heartbeats, so offline devices stay pending. If a run does not move, check
each device's action and its recent heartbeats. A payload that cannot be fetched always shows up as a failed action.

Audit events go to `Logger` and the `script_audit` PubSub topic. There is no audit table, so how long they are kept
depends on your log collection.

The workbench adds no package installation and no server-side Starlark parser. The server's validation is deliberately
limited, and does not replace the device's own runtime.

## Differences from the design

- **Fetching large scripts.** The poll loop fetches deferred `run_script` payloads, rather than giving the command
  handler a second way to reach the server.
- **Audit in logs.** Audit events are Logger and PubSub events, not a new table; your log collection keeps them.
- **No JSON:API routes.** Script records stay internal to the Ash domain, with no generic JSON:API routes.

## Not included

- There is no full Starlark parser on the server.
- There are no external API actions for scripts.
- There is no paging, high-volume run retention, or richer editor beyond what is described here.
- Automated tests don't deploy to a live device through the browser; that needs the Compose device lab.
- There is no server-only Starlark dialect, no automatic fleet-wide deployment, no remote shell, no audit table, and no
  package management.

## Tests

- `packages/server/test/nixstasis/scripts_test.exs`: drafts, fixed versions, validation, tests, deployments, retries,
  cancelling, and each device's actions.
- `packages/server/test/nixstasis/scripts/validator_test.exs`: the front matter, schema, and Starlark checks.
- `packages/server/test/nixstasis/scripts/authorization_test.exs`: checking targets.
- `packages/server/test/nixstasis/scripts/audit_test.exs`: naming the operator in audit events.
- `packages/server/test/nixstasis_web/live/script_live_test.exs`: the `/scripts` list and editor.
- `packages/server/test/nixstasis_web/controllers/script_json_api_test.exs`: workbench records are not exposed as
  JSON:API routes.
- `packages/client/cmd/nixstasis/poll_test.go`: fetching deferred `run_script` payloads in the poll loop.
- `packages/client/internal/commands/handler_test.go`: handling `run_script` and `install_script`.
- The Stary runtime tests in `packages/client/internal/script/`: parsing, schemas, running scripts, and compatibility
  with rendered versions.
- `mix format --check-formatted`, `gofmt`, and `rumdl`.

## Related pages

- [Stary Script Workbench](../../operations/script-workbench.md)
- [Server Scripts](../../modules/server-scripts.md)
- [Client-Server Interface](../../client-server-interface.md#server-managed-stary-command-contract)
- [Client Command Handler](../../modules/client-command-handler.md)
- [Client Starlark Runtime](../../modules/client-starlark-runtime.md)
- [API & Runtime Contracts](../../reference/contracts.md)
- [Server Web](../../modules/server-web.md)
- [Architecture Overview](../../architecture.md)
