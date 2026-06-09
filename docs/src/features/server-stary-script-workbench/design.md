# Server Stary Script Workbench

## Feature Name

`server-stary-script-workbench`

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
  Starlark parseability before a script can be queued for test or deployment.
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

### Validation Boundary

Server-side validation gives fast feedback for syntax, front matter, and schema
shape. It must use the same Stary format expectations as the Go client. The
server may implement validation directly or invoke a packaged validation helper,
but it must not diverge from client acceptance rules.

Runtime validation remains client-owned. Test results must preserve client
failure reasons, including schema mismatch, runtime exceptions, timeout, and
`exec_cmd` allowlist rejection.

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
actions. Audit records should include actor identity, action, script version,
target clients, timestamps, and per-client result summaries.

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
- Existing command delivery concepts should be reused where practical, but the
  command contract may need a test-only script execution mode.
- Script content can be larger than a normal inline heartbeat command. Test and
  deploy commands should use the existing deferred command payload mechanism
  when payload size or retention rules make inline delivery risky.
- The client may need a command handler path that executes provided script
  content without installing it.
- The client may need to report richer script test results than the existing
  install/remove command responses.
- If command request or result shapes change, the durable API contract must be
  reflected in the retained device API reference and client/server compatibility
  tests.
- If new Ash resources are added for script persistence, generate named Ash
  migrations and snapshots before the reviewed implementation is closed.

## User-Facing Documentation Impact

- Development: document how operators and developers validate Stary scripts from
  the server UI.
- Operations: document authorization, audit, rollout, and failure handling for
  server-managed script deployment.
- Architecture: document the server authoring boundary and the client execution
  boundary.
- Reference: update device command or API contracts if test/deploy payloads
  become durable interfaces.

## Validation

- Server tests for script draft/version persistence, validation transitions,
  test/deploy authorization, audit events, and result recording.
- Parser/validation contract tests that prove server-side validation accepts and
  rejects the same Stary front matter and schemas as the Go client.
- LiveView tests for front-matter editing, script body editing, validation
  feedback, client selection, test execution, deployment confirmation, and
  per-client result states.
- Client command tests for test-only execution and install/update behavior,
  including timeout, invalid schema, malformed script, runtime failure, and
  command allowlist rejection.
- End-to-end test that creates a draft in the UI, validates it, tests it on one
  or more clients, deploys it to selected clients, and observes the resulting
  telemetry behavior.
