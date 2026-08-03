# Server Stary Script Workbench

## Delivery Summary

- Beads feature root: `nixstasis-kb6`
- Status: delivered
- Pull request: not created; no PR action was selected
- Merge commit: `bfda24f3ddb27493f9b453d5aed4f98807553dd3` (fast-forward into `dev`)
- Design record: [design.md](design.md)

The implementation, close-out reconciliation, validation, and Beads evidence were
fast-forwarded into `dev`.

## Delivered Capability

Operators can create and edit Stary drafts in Phoenix, validate the rendered artifact,
select authorized devices for test execution, inspect per-client results, and deploy a
validated version through the existing authenticated device command path. The server
retains drafts, immutable versions, validation runs, test/deployment runs, and per-client
actions without exposing generic script CRUD through Ash JSON:API.

## User-Facing Behavior

- `/scripts` lists drafts and `/scripts/:id` provides the editor and run history.
- Validation provides bounded front-matter, schema-shape, and conservative Starlark
  feedback before queueing.
- Test runs use `run_script` and do not install the candidate into the client's polling
  script directory.
- Deployment uses `install_script` and the immutable `ScriptVersion.rendered_content`
  artifact.
- Target selection is checked at the context boundary against trusted device scope;
  empty, unauthorized, and mixed selections do not create partial side effects.
- Retry and cancellation are visible for active or failed runs, with delayed heartbeat
  delivery represented as pending client actions.
- Operator audit events carry trusted actor identity. Device-originated results remain
  attributed to the authenticated device.

## Design Integration

Phoenix owns authoring, bounded preflight, durable workbench state, target authorization,
audit emission, and orchestration. `Nixstasis.Devices` and `Nixstasis.Monitoring` retain
device authentication, pending-command ownership, heartbeat delivery, and result transport.
The Go client remains authoritative for Stary parsing, builtins, command policy, timeouts,
output validation, and runtime execution.

Large rendered artifacts use the existing deferred command-payload flow. The server retains
the payload by reference; the Go poll loop hydrates it before invoking the command handler.
The existing `/api/v1` device protocol remains the compatibility surface.

## Operational Impact

Script commands are delivered when devices heartbeat, so offline targets remain pending.
Operators should inspect per-client action state and device heartbeat health when a run does
not advance. Deferred payload failures are deterministic failed client actions. Audit events
are written to `Logger` and broadcast on `script_audit` PubSub; there is no application audit
table, so durable retention follows deployment structured-log policy.

No new package installation or runtime parser dependency was introduced. The server
validator remains intentionally bounded and does not replace the client runtime.

## Reference and Contracts

- [Stary Script Workbench operations](../../operations/script-workbench.md)
- [Server Scripts](../../modules/server-scripts.md)
- [Client-Server Interface](../../client-server-interface.md)
- [Client Command Handler](../../modules/client-command-handler.md)
- [Client Starlark Runtime](../../modules/client-starlark-runtime.md)
- [API & Runtime Contracts](../../reference/contracts.md)
- [Server Web](../../modules/server-web.md)

## Validation Evidence

- `mise x -- mix test test/nixstasis/scripts_test.exs test/nixstasis_web/live/script_live_test.exs` — 52 tests, 0 failures.
- `mise x -- mix precommit` — 589 server tests, 0 failures.
- `mise x -- go test ./cmd/nixstasis ./internal/commands ./internal/transport` — passed for deferred command hydration and command handling.
- Focused Go Stary runtime tests — passed for parsing, schema, execution, and immutable-artifact compatibility.
- Focused `mix format --check-formatted`, `gofmt`, `rumdl`, and `git diff --check` — passed.
- Repository-wide Markdown validation retains the repository's known legacy warnings; no new error was introduced by this feature.

## Design Reconciliation

### Delivered as Designed

- Server-side bounded validation and canonical rendering.
- Immutable version artifacts used by validation, test, and deployment.
- Context-level target authorization and trusted actor attribution.
- Existing heartbeat, pending-command, command-result, and deferred-payload transport.
- Client-side Stary runtime authority and deny-by-default command policy.

### Intentional Changes

- Deferred `run_script` hydration was completed in the Go poll loop rather than adding a
  second command-handler transport dependency.
- Audit events remain Logger/PubSub events rather than a new persistence system; deployment
  structured logging owns durable retention.
- Script persistence remains internal Ash domain state instead of generic JSON:API CRUD.

### Deferred Work

- A packaged, supervised server Starlark parser/helper remains deferred.
- External audited domain-specific script API actions remain future work.
- Pagination, high-volume run retention, and richer editor capabilities remain outside the
  initial workbench scale.
- Browser smoke/E2E deployment against a live managed client remains a close-out validation
  limitation when the Compose device environment is unavailable.

### Rejected or Removed Scope

- No server-only Starlark dialect was introduced.
- No automatic fleet-wide deployment or arbitrary remote shell was added.
- No separate audit table or package-management framework was introduced.

## Documentation Updated

- `docs/src/operations/script-workbench.md`
- `docs/src/modules/server-scripts.md`
- `docs/src/architecture.md`
- `docs/src/client-server-interface.md`
- `docs/src/reference/contracts.md`
- `docs/src/modules/client-command-handler.md`
- `docs/src/modules/client-starlark-runtime.md`
- `docs/src/modules/server-web.md`
- `docs/src/planned-features.md`
- `docs/src/features/index.md`
- `docs/src/SUMMARY.md`

## Audit Trail

Specification review and reconciliation are recorded in Beads under `nixstasis-kb6.2`–
`nixstasis-kb6.6`. Implementation children `nixstasis-kb6.7.41`–`.44` and coordinator
`nixstasis-kb6.7` are closed.

Implementation commits:

- `197c2d5cf2e1f175e2cbb940975613ada65b484b` — immutable validation artifacts.
- `4a9682873bd2dbb79bfa239b16eaf4ae7f290e07` — deferred `run_script` payload hydration.
- `49f928d3b263083db1e49834ae0d358b302874c2` — trusted audit actor identity.
- `356bb9b81a9042a2c3ffc24260fcbb4edb29abda` — context-level target authorization.

Close-out documentation and validation are tracked by `nixstasis-kb6.8` and
`nixstasis-kb6.9`; delivery review and drift review are closed under `.10` and `.11`.
`bfda24f3ddb27493f9b453d5aed4f98807553dd3` records the fast-forward delivery and
includes the feature's Beads interaction evidence. No remote push or pull request was
performed.
