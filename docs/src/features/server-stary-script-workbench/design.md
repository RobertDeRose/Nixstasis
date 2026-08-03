<!-- workflow-migration:legacy-markdown-to-beads -->

# Server Stary Script Workbench

## Feature Name

`server-stary-script-workbench`

## Metadata

- Beads feature root: `nixstasis-kb6`
- Design path: `docs/src/features/server-stary-script-workbench/design.md`
- Implemented record: `docs/src/features/server-stary-script-workbench/index.md`
- Base branch: `dev`
- Implementation repository: `nixstasis`
- Implementation path: `/Users/DeRoseR/workspace/personal/nixstasis`
- Status: in progress

## Specification Reconciliation

- The server validator provides bounded front-matter, schema-shape, and
  conservative structural preflight; the Go client remains authoritative for
  complete Starlark parsing and runtime enforcement.
- Script target authorization belongs in `Nixstasis.Scripts`, not only in the
  LiveView's filtered device list.
- Audit events carry trusted actor identity for operator actions; device result
  ingestion remains device-authenticated and separately attributable.
- Inline `run_script` payloads remain the compatibility baseline. Deferred
  `run_script` hydration is a required implementation child and is not silently
  treated as already supported by the client.
- `ScriptVersion.rendered_content` is the immutable artifact boundary; validation
  runs must reference the version that produced the artifact and duplicate or
  failed validation paths must be deterministic.
- The imported T001-T026 implementation records remain historical provenance;
  current gaps are represented by bounded children `nixstasis-kb6.7.41` through
  `nixstasis-kb6.7.44`, each blocked by `nixstasis-kb6.6`.

## Goal

Provide a server web interface for creating, editing, validating, testing, and
deploying Stary scripts while preserving the existing client runtime as the
authoritative execution boundary.

## Users

- Operators who maintain telemetry scripts for managed devices.
- Administrators who need auditability around script changes and deployment.
- Developers validating scripts against real client behavior before rollout.

## Requirements

- Provide a script inventory with draft, validated, tested, deployed, failed, and
  archived states.
- Provide a structured front-matter editor for script name, version, output
  schema, and supported metadata from the existing `stary` format.
- Provide a Starlark body editor suitable for editing the script content.
- Validate YAML front matter, Stary file structure, declared output schema, and
  conservative server-side Starlark structure before queueing; the selected
  client performs authoritative Starlark parsing and runtime validation before
  execution.
- Reuse existing client Stary semantics; do not introduce a server-only dialect.
- Allow an operator to select one or more clients for test execution.
- Dispatch test runs through the authenticated device command path or an
  explicitly designed successor contract.
- Capture per-client test status, output, warnings, validation errors, execution
  errors, timeout results, and command allowlist rejections returned by the
  client runtime.
- Keep test runs separate from deployed polling scripts.
- Deploy a validated script to selected clients only after an explicit operator
  action.
- Record script versions, validation results, test results, deployment targets,
  actor identity, timestamps, and per-client deployment acknowledgements.
- Surface test and deployment failures without blocking unrelated clients from
  normal telemetry reporting.

## Constraints

- The client remains authoritative for Starlark builtins, command allowlisting,
  timeouts, and output validation.
- Server-side validation must not require an unmanaged client binary in
  production unless that dependency is deliberately packaged and supervised.
- Test and deploy commands must be authenticated, authorized, bounded by timeout,
  and rate limited.
- Draft scripts and test results may contain sensitive operator-authored logic or
  device output and must follow operator-only device-control authorization.
- Deployment must preserve client-side safeguards for malformed scripts, schema
  mismatches, denied commands, forbidden builtins, and timeout behavior.

## Non-Goals

- Replacing client-local `test_script`, `repl`, `list_scripts`,
  `install_script`, or `remove_script` workflows.
- Building a collaborative IDE with real-time multi-user editing.
- Providing full source-control semantics for scripts in the first increment.
- Automatically deploying scripts to every client without explicit target
  selection.
- Designing a new scripting language or changing Stary file syntax.
- Implementing command allowlist management as part of this feature.

## Proposed Design

### Current Runtime Baseline

The existing client runtime already defines the operational shape this feature
must preserve:

- `ParseStaryFile` and `ParseStaryContent` require `---` front matter, YAML
  decode into `FrontMatter`, a non-empty script name, and a non-nil schema.
- `DiscoverScripts` scans the system and user script directories, ignores
  non-`.stary` files, and skips invalid scripts rather than failing the whole
  poll cycle.
- `Executor.ExecuteScripts` shares a single runtime per poll cycle, executes up
  to 20 scripts in parallel, and returns a result map keyed by script name.
- `Runtime.Execute` requires a callable `main()`, enforces the configured
  timeout, and converts Starlark return values to Go maps.
- `install_script` validates front matter, schema, version, and script name
  shape before writing into the user install directory.
- `remove_script` resolves duplicate script names by latest version when
  possible, otherwise requires path selection.
- `script test` resolves scripts by path or name, prints YAML output on success,
  and preserves validation/runtime errors as non-success exits.
- `exec_cmd` is deny-by-default and only succeeds when the runtime allowlist
  maps the requested command to an absolute executable path.

### Current Server Delivery Baseline

The server already has the building blocks for queued device commands and
heartbeat-driven delivery:

- `Monitoring.heartbeat/2` updates `last_seen_at`, persists telemetry, resolves
  offline alerts, evaluates rule alerts, and then pops pending commands.
- `Devices.pop_pending_commands/1` is the delivery boundary that claims queued
  commands for a device during heartbeat processing.
- `PendingCommand` stores `command_payload`, `status`, `queued_at`,
  `delivered_at`, and the owning `device`.
- `DeviceCommandController.command_results/2` authenticates the device, accepts a
  list of command results, and calls `Devices.acknowledge_command_results/2`.
- `DeviceCommandController.command_payload/2` serves deferred command payloads by
  reference and returns `404` when a payload is missing.
- The client transport already models `CommandRequest`, `CommandPayload`,
  `CommandResult`, `PollResponse`, `FetchCommandPayload`, and `SendCommandResults`.
- `CommandRequest` already includes `payload` and `payload_ref`, so commands can
  be delivered inline or by deferred payload.
- The heartbeat path is already the place where command delivery and remote
  access intent are co-resident.

### Test And Payload Contract

The workbench uses the existing device command transport rather than creating a
separate testing API:

- Test execution is represented as a new command type, `run_script`.
- `run_script` carries immutable rendered `.stary` content as a `command_payload`.
- The current inline path is the compatibility baseline for small payloads.
- Large payloads use `payload_ref` and fetch through
  `GET /api/v1/devices/:device_id/command_payloads/:ref`; completing that
  `run_script` hydration path is an explicit implementation child before this
  boundary is considered complete.
- The payload `content_type` identifies Stary script text so the client can
  distinguish it from install/remove payloads.
- The client responds through the existing
  `POST /api/v1/devices/:device_id/command_results` endpoint with a single
  command result per execution attempt.
- The result envelope preserves client-side script execution status, output,
  warnings, validation status, error type, error message, and timing data when
  available.
- A missing deferred payload remains a normal `404` contract and surfaces as a
  failed test result without installing or executing draft content.
- Deployment continues to use the existing `install_script` command shape for
  installed script artifacts.

### Script Draft Model

The server stores script drafts and versions as durable records. A draft holds
front matter as structured data plus the Starlark body as text. The server can
render the canonical `.stary` content from those fields before validation, test,
or deployment.

The script lifecycle is explicit:

1. Draft: editable content exists but has not passed validation.
2. Validated: server-side parsing/schema checks pass for the rendered script.
3. Tested: at least one selected client has executed the draft as a test and
   returned a result.
4. Deployed: a script version was installed on one or more selected clients.
5. Failed: the latest validation, test, or deployment action failed.
6. Archived: a script is hidden from active authoring and deployment workflows.

Status should be derived from version/action records where practical rather than
being a fragile single mutable field.

The feature should use a small, explicit state vocabulary for the persisted
objects involved in the workbench:

- Script draft status: `draft`, `validated`, `archived`.
- Script version status: `candidate`, `validated`, `deployed`, `superseded`,
  `archived`.
- Validation run status: `pending`, `passed`, `failed`.
- Test run status: `pending`, `running`, `passed`, `failed`, `timed_out`,
  `unsupported`, `unavailable`.
- Deployment run status: `pending`, `running`, `deployed`, `partial`,
  `failed`.
- Per-client action status: `queued`, `delivered`, `acknowledged`, `failed`,
  `missing_payload`.

### Validation Boundary

Server-side validation gives fast feedback for front matter, schema shape, and
conservative Starlark structure. `Nixstasis.Scripts.Validator` owns that
bounded preflight and canonical rendering; it does not claim to be a complete
Starlark parser or a replacement for the Go client. A packaged supervised
parser/helper remains deferred until its packaging and supervision boundary is
separately designed.

The Go client remains authoritative for Stary parsing, schema compilation,
builtins, output validation, execution errors, timeouts, and `exec_cmd`
allowlisting. The server must preserve the exact rendered artifact and client
failure reasons, including schema mismatch, runtime exceptions, timeout, and
allowlist rejection. Server preflight failure prevents queueing; client
validation or execution failure remains a normal per-client result.

### Test Execution

Testing a draft sends rendered script content to selected clients as a test-only
operation. The client executes the content without installing it into the normal
polling script directory. Each client returns a result envelope with status,
output, warnings, validation status, error type, error message, and timing data
where available.

Testing must be safe for offline clients and delayed polling. The UI should show
pending, running, succeeded, failed, timed out, unsupported, and unavailable
states per selected client.

### Deployment

Deployment installs a validated script version on explicitly selected clients
through the device command flow or a successor contract. Deployment state is
tracked per client so partial success is visible. Deployment must not obscure
normal heartbeat or telemetry failures.

### UI Shape

The LiveView surface should include:

- A script inventory with status, version, updated time, and last action result.
- A focused editor view with front-matter fields and script body editing.
- A validation result panel.
- A client selection and test result panel.
- A deployment confirmation flow with selected clients and version summary.

The editor can use a simple textarea in the first implementation if richer code
editing would create unnecessary scope. The front-matter editor should be
structured enough to prevent malformed metadata from routine UI edits.

### Authorization And Audit

Script authoring, testing, and deployment are operator-only device-control
actions. The `Nixstasis.Scripts` context is the authorization boundary: it must
validate every target against the trusted session's device scope before creating
commands or run records. LiveView filtering is a presentation optimization, not
a security control.

Audit records include the trusted actor identity, action, script version, target
clients, timestamps, and per-client result summaries. Device-originated command
results remain attributed to the authenticated device. The audit sink and
retention policy are documented explicitly rather than implied to be durable
application records.

## Edge Cases

- Invalid YAML front matter or missing front matter.
- Invalid JSON Schema in front matter.
- Starlark parse errors.
- Runtime failure on one client while another succeeds.
- Offline clients selected for test or deployment.
- Duplicate script names or non-incrementing versions.
- A test command is delivered more than once by retry or polling behavior.
- A script uses a builtin unavailable on an older client.
- `exec_cmd` is present but the selected client rejects the command by policy.
- A deployed script version is overwritten or removed locally on the client.

## Data And Contract Notes

- New server persistence is expected for script drafts, script versions, test
  runs, deployment runs, and per-client action results.
- These Ash resources are internal domain records and intentionally omit generic
  JSON:API routes. The current LiveView calls the domain directly; a future
  external contract requires audited, domain-specific actions rather than raw
  CRUD exposure.
- `ScriptVersion.rendered_content` is the one immutable artifact used for
  validation, test, and deployment. A validation run references the version that
  produced it, and repeated validation has deterministic duplicate-version
  behavior.
- Existing command delivery concepts are reused for `run_script` and
  `install_script`. Inline payloads remain the baseline; deferred `run_script`
  hydration, missing-payload handling, and retention are explicit follow-up
  contract work.
- The client command handler executes provided test content without installing
  it and reports structured result envelopes through the existing result route.
- If command request or result shapes change, the durable API contract must be
  reflected in the retained device API reference and client/server compatibility
  tests.
- If new Ash resources are added for script persistence, generate named Ash
  migrations and snapshots before the reviewed implementation is closed.

## User-Facing Documentation Impact

| Documentation concern      | Exact page                                                 | Create or update        | Planned change                                                                                                                     | Owning task       |
|----------------------------|------------------------------------------------------------|-------------------------|------------------------------------------------------------------------------------------------------------------------------------|-------------------|
| Development / operations   | `docs/src/operations/script-workbench.md`                  | Create                  | Document authoring, validation, target authorization, audit, rollout, retries, cancellation, and failure handling.                 | `nixstasis-kb6.8` |
| Architecture               | `docs/src/modules/server-scripts.md`                       | Create                  | Document Phoenix authoring/orchestration, Ash persistence, command delivery, and the client execution boundary.                    | `nixstasis-kb6.8` |
| Architecture               | `docs/src/architecture.md`                                 | Update                  | Add the server authoring/client execution boundary and script-workbench flow.                                                      | `nixstasis-kb6.8` |
| Reference                  | `docs/src/client-server-interface.md`                      | Update                  | Document `run_script`, inline/deferred payloads, result envelopes, and retained `/api/v1` behavior when the contract is finalized. | `nixstasis-kb6.8` |
| Reference                  | `docs/src/reference/contracts.md`                          | Update                  | Link the durable script command boundary and state that internal Ash records have no generic JSON:API routes.                      | `nixstasis-kb6.8` |
| Reference                  | `docs/src/modules/client-command-handler.md`               | Update                  | Add `run_script`, test-only execution, deferred hydration, and failure behavior.                                                   | `nixstasis-kb6.8` |
| Architecture               | `docs/src/modules/client-starlark-runtime.md`              | Update                  | Clarify that server-managed tests still use the Go runtime and preserve local safeguards.                                          | `nixstasis-kb6.8` |
| Navigation                 | `docs/src/SUMMARY.md`                                      | Update                  | Register both new reader-facing pages and the implemented feature record.                                                          | `nixstasis-kb6.8` |
| Implemented feature record | `docs/src/features/server-stary-script-workbench/index.md` | Create during close-out | Preserve delivered behavior, evidence, decisions, limitations, and audit history.                                                  | `nixstasis-kb6.8` |

## Validation

- Server tests for script draft/version persistence, validation transitions,
  test/deploy authorization, audit events, and result recording.
- Parser/validation contract tests that prove server front-matter and schema
  preflight agrees with representative Go-client acceptance cases; the Go client
  remains the authority for complete Starlark parsing and runtime behavior.
- LiveView tests for front-matter editing, script body editing, validation
  feedback, client selection, test execution, deployment confirmation, and
  per-client result states.
- Client command tests for test-only execution and install/update behavior,
  including timeout, invalid schema, malformed script, runtime failure, and
  command allowlist rejection.
- End-to-end test that creates a draft in the UI, validates it, tests it on one
  or more clients, deploys it to selected clients, and observes the resulting
  telemetry behavior.

## Implementation Notes

### Starlark Validation Deferred

The current server validator performs front-matter, schema-shape, and
conservative structural preflight. It is intentionally not a complete Elixir
Starlark parser and does not replace the Go runtime. A packaged, supervised
Starlark parser/helper remains deferred; until then, the client performs final
parse, schema, output, builtin, timeout, and execution enforcement.

### Render Value Encoding

`render_value/1` in `Validator` uses `Jason.encode!` for maps and lists to
produce YAML-compatible output. This enables round-trip render/validate
consistency. Earlier versions used `inspect/1` which produced Elixir syntax
(quotes, atoms) that YAML parsers could not re-read.

### Domain Function Return Types

Ash domain list functions (`list_script_drafts`, `list_script_versions`, etc.)
return `{:ok, list}` tuples. The `Devices.list_devices/1` context function
uses `Ash.read!/1` and returns a bare list. LiveViews must handle both patterns.

### LiveView Layout Convention

This project does not use `<Layouts.app>` inside LiveView templates. The
`app.html.heex` root layout wraps `{@inner_content}` automatically via the
router's `put_root_layout` plug. Templates render their content directly without
the layout wrapper.

### Validated Version Boundary

Validation requires an explicit non-empty front-matter `version`. Test and
deployment commands use the persisted `ScriptVersion.rendered_content`, not the
current mutable draft body, so the client executes the exact artifact that
passed validation. The validation run records the associated version and
revalidation of an existing version has deterministic behavior.

### Run Refresh And Stuck Runs

The Script Workbench subscribes to script run PubSub events and also polls as a
fallback while connected. Test and deployment runs expose retry actions for failed
or partial runs. Active runs can be cancelled from the UI by marking the server
run failed; already delivered client commands may still complete independently.

## Feature Summary

Provide a server UI for authoring, validating, testing, versioning, deploying, retrying, and auditing Stary scripts
while preserving the Go client as the authoritative execution boundary.

## User Intent

Operators need to manage telemetry scripts centrally, test immutable validated versions on selected devices, and inspect
per-device outcomes before controlled rollout.

## Goals

Provide auditable authoring, immutable validation, selected-device testing, explicit deployment, and actionable results.

## User-Facing Behavior

The workbench exposes draft and version inventories, structured front matter, code editing, validation feedback, device
selection, test and deployment runs, live status refresh, retry, cancellation, and per-device results.

## Existing Context

The completed Starlark runtime, deferred command payloads, device command results, Ash resources, LiveView conventions,
and command-policy enforcement are reused.

## Architecture Consistency

Phoenix owns authoring, durable versions, trusted target authorization, audit,
and orchestration. The client owns parser fidelity, builtins, timeouts, output
validation, and final execution enforcement. Internal script Ash resources are
not generic JSON:API resources; domain-specific actions remain the future
external-contract boundary.

## Operational Considerations

Runs are bounded, authorized at the context boundary, auditable with trusted actor
identity, and visible when devices are offline or partial. Inline payloads are the
current baseline; deferred payloads have an explicit follow-up contract. Immutable
rendered content prevents a mutable draft from differing from the artifact that
was validated and dispatched. Run listing/refresh uses the current initial-scale
LiveView approach; pagination and retention are deferred until operational volume
requires them.

## Documentation Impact

The exact reader-facing pages are listed in the User-Facing Documentation
Impact table above. The two new pages are
`docs/src/operations/script-workbench.md` and
`docs/src/modules/server-scripts.md`; product documentation must not require
this internal design page for usage or operations guidance.

## Validation Strategy

Run server resource, state transition, authorization, LiveView, validator, PubSub, and audit tests; run client command
and runtime tests; finish with a Compose browser smoke test and documentation validation.

## Implementation Decomposition

The imported T001-T026 records remain closed historical provenance. The remaining
bounded implementation children are:

- `nixstasis-kb6.7.41`: enforce device-scoped authorization at the script context boundary.
- `nixstasis-kb6.7.42`: preserve trusted actor identity and document the audit sink/retention boundary.
- `nixstasis-kb6.7.43`: complete deferred `run_script` payload delivery and compatibility tests.
- `nixstasis-kb6.7.44`: align immutable artifact rendering, validation-run/version relationships, duplicate-version behavior, and failed-validation records.

Each remaining child depends on `nixstasis-kb6.6` and is independently testable. Delivered slices include persistence, editor UI, baseline validation, immutable versions, inline test/deployment dispatch, result display, retry, cancellation, and live refresh.

## Dependencies and Parallelism

All remaining implementation children depend on specification reconciliation. Target
authorization and audit identity are server-context work; deferred payloads span
server transport and the Go command handler; artifact/validation alignment is
server-domain work. They can proceed in parallel after `.6`, with final
compatibility and browser validation in `.9`.

## Risks and Tradeoffs

Central authoring improves fleet control but increases remote-execution, authorization, audit, versioning, and partial
failure complexity. Server validation may lag client semantics until the packaged helper is delivered.

## Rejected Alternatives

A separate server scripting dialect, automatic fleet-wide rollout, and treating server validation as runtime authority
remain rejected.

## Open Questions

The remaining open evidence is final browser smoke coverage and documentation reconciliation.

## Deferred Decisions

A packaged Starlark parse helper and collaborative IDE behavior remain deferred.
