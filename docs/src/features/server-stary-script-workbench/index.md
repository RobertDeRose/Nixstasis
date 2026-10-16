# Server Stary Script Workbench

## References

- Beads feature root: `nixstasis-kb6`
- Design record: [design.md](design.md)

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

## Test Coverage

- `packages/server/test/nixstasis/scripts_test.exs`: drafts, immutable versions, validation, test and deployment runs,
  retry, cancellation, and per-client actions.
- `packages/server/test/nixstasis/scripts/validator_test.exs`: bounded front-matter, schema-shape, and Starlark
  preflight.
- `packages/server/test/nixstasis/scripts/authorization_test.exs`: context-level target authorization.
- `packages/server/test/nixstasis/scripts/audit_test.exs`: trusted actor attribution in audit events.
- `packages/server/test/nixstasis_web/live/script_live_test.exs`: `/scripts` list and editor workflows.
- `packages/server/test/nixstasis_web/controllers/script_json_api_test.exs`: workbench resources are not exposed as
  generic JSON:API routes.
- `packages/client/cmd/nixstasis/poll_test.go`: deferred `run_script` payload hydration in the poll loop.
- `packages/client/internal/commands/handler_test.go`: `run_script` and `install_script` command handling.
- Go Stary runtime tests under `packages/client/internal/script/`: parsing, schema, execution, and immutable-artifact
  compatibility.
- Repository formatting and Markdown checks: `mix format --check-formatted`, `gofmt`, and `rumdl`.

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
- Browser smoke/E2E deployment against a live managed client requires the Compose device
  environment and is not part of automated coverage.

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
