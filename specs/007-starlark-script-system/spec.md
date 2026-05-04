# Feature Specification: Stary Script Support

**Feature Branch**: `007-starlark-script-system` **Created**: February 8, 2026 **Status**: Draft **Input**: User description: "Replace Go client plugin system with embedded StarLark scripting using stary files (StarLark + YAML front-matter output schema)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run a Stary Script (Priority: P1)

As a client user, I want to run a `stary` script that declares its output schema, so I can extend client behavior with predictable outputs.

**Why this priority**: This is the core value of replacing the plugin system and enables the primary extension workflow.

**Independent Test**: Provide a valid `stary` file with YAML front-matter and run it; confirm a validated output is produced.

**Acceptance Scenarios**:

1. **Given** a valid `stary` file with YAML front-matter defining an output schema and a script body that produces matching output, **When** the user runs the script, **Then** the client executes it and returns output that conforms to the declared schema.
2. **Given** multiple valid `stary` files, **When** the user selects one to run, **Then** only the selected script executes and returns its validated output.

---

### User Story 2 - Detect and Explain Script Errors (Priority: P2)

As a client user, I want clear, actionable errors when a script or schema is invalid, so I can fix issues quickly.

**Why this priority**: Without reliable feedback, scripts are costly to debug and adoption suffers.

**Independent Test**: Run a script with invalid YAML front-matter or mismatched output and verify error messaging and rejection behavior.

**Acceptance Scenarios**:

1. **Given** a `stary` file with invalid or missing YAML front-matter, **When** the user runs the script, **Then** the client rejects it and reports the specific front-matter issue.
2. **Given** a `stary` file whose script output does not match the declared schema, **When** the user runs the script, **Then** the client reports which fields failed validation and does not return a successful output.

---

### User Story 3 - Discover, Install, and Remove Scripts (Priority: P3)

As a client user, I want to list available `stary` scripts and install/remove them, so I can manage multiple scripts confidently.

**Why this priority**: Projects commonly include more than one script, and selection is necessary for day-to-day use.

**Independent Test**: Provide a folder with multiple `stary` files and confirm the user can list, install, and remove scripts as expected.

**Acceptance Scenarios**:

1. **Given** a location containing multiple `stary` files, **When** the user requests available scripts, **Then** the client lists them with enough information to choose the correct one.
2. **Given** a valid `stary` file path, **When** the user runs `nixstasis script install`, **Then** the script is validated and installed or a clear error is returned.
3. **Given** an installed script name, **When** the user runs `nixstasis script remove`, **Then** the script is removed and the action is confirmed.

---

### User Story 4 - Test and REPL for Scripts (Priority: P4)

As a client user, I want to test a `stary` script from the CLI and start a Starlark REPL with builtins available, so I can iterate quickly without full polling.

**Why this priority**: Enables faster script development and debugging without waiting for the full telemetry loop.

**Independent Test**: Run `nixstasis script test` against a valid script and verify pretty-printed output; start the REPL and call a builtin.

**Acceptance Scenarios**:

1. **Given** a valid `stary` file path, **When** the user runs `nixstasis script test <path>`, **Then** the client executes the script and prints its output in a pretty-printed format.
2. **Given** the user runs `nixstasis script repl`, **When** the REPL starts, **Then** Starlark builtins (including `pub_and_get` and deny-by-default `exec_cmd`) are available for interactive use.

---

### Edge Cases

- What happens when a `stary` file has YAML front-matter but no script body?
- How does the system handle multiple scripts with the same display name or identifier?
- What happens when a script returns a partial output that is missing required fields?
- How does the system handle scripts that take too long to complete?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST accept user-provided `stary` files and execute the contained script when requested.
- **FR-002**: Each `stary` file MUST include YAML front-matter that defines an output schema; files missing or failing schema definition validation MUST be rejected with a clear error.
- **FR-003**: System MUST validate the script output against the declared schema and report field-level validation failures.
- **FR-004**: Users MUST be able to select which `stary` script to run by file path or unique identifier.
- **FR-005**: System MUST return a clear success/failure result for each script execution, including validation status.
- **FR-006**: System MUST surface actionable errors for script parsing, execution, and schema validation that identify the file and failure type.
- **FR-007**: System MUST allow multiple `stary` scripts to coexist within the same project or workspace.
- **FR-008**: System MUST provide a built-in Starlark function `pub_and_get(topic, msg, reply_topic=nil, accept=nil)` that publishes to `topic`, subscribes to `reply_topic` (defaulting to `topic`), and returns the first response matching `accept` within 5 seconds. `accept` is a map of key/value pairs that must all be present in the JSON response payload; responses missing any required key or value are ignored.
- **FR-009**: System MUST provide a built-in Starlark function to execute OS commands with a restricted user and a command blacklist; blocked commands MUST return a clear error.
- **FR-010**: Script selection identifiers are either the script `name` from front-matter or an explicit file path. If names conflict, path selection MUST be used.
- **FR-011**: Each script execution MUST return a structured result containing `status` (success/error/timeout), `validation_status`, and any `warnings` (including slow execution >3s).
- **FR-012**: The server MAY include queued client commands in the heartbeat response; the client MUST execute all received commands and respond as soon as command processing completes.
- **FR-013**: The client MUST send a single aggregated command-results response immediately after processing the heartbeat command batch.
- **FR-014**: Each command MUST return a result of `OK` or `FAILED`; failures MUST include a reason, and results MAY include command-specific output.
- **FR-015**: Each command MUST time out after 5 seconds; timeouts MUST be reported as failures.
- **FR-016**: Each heartbeat command MUST include a `command_id`, and each command result MUST include the same `command_id` for correlation.
- **FR-017**: The CLI MUST provide `nixstasis script test <path>` to execute a `stary` script and pretty-print its output as YAML.
- **FR-018**: The CLI MUST provide `nixstasis script repl` to start a Starlark REPL with builtins available.
- **FR-019**: The client SHOULD execute heartbeat commands in parallel when possible and aggregate results at the end of the batch.
- **FR-020**: If duplicate `command_id` values appear in the same heartbeat batch, the client MUST ignore later duplicates and return `FAILED` with reason `duplicate_command_id` for those entries.
- **FR-021**: The client MUST send the aggregated command-results response within 1 second after the last command finishes (or times out).
- **FR-022**: If `nixstasis script test` fails (parse, execution, validation, or timeout), it MUST print error details and exit non-zero without pretty-printing output.

### Key Entities *(include if feature involves data)*

- **Stary Script**: A user-authored file that combines YAML front-matter and a script body.
- **Output Schema**: The schema declared in YAML front-matter that defines expected output fields and types.
- **Script Output**: The data produced by a script execution.
- **Execution Result**: The success/failure status, validation details, and associated errors for a script run.
- **HeartbeatCommand**: `command_id` (string), `type` (string), `payload` (object).
- **HeartbeatCommandResult**: `command_id` (string), `status` (`OK` | `FAILED`), `output` (object, optional), `error` (string, optional).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 95% of valid `stary` scripts execute and return schema-validated output within 2 seconds under typical project sizes.
- **SC-002**: 100% of invalid YAML front-matter cases are rejected with a clear, user-actionable error identifying the file and issue.
- **SC-003**: 100% of schema mismatches report the specific fields that failed validation.
- **SC-004**: Users can add and run a new `stary` script in under 5 minutes without support intervention.

## Assumptions

- `stary` files use standard Starlark with YAML front-matter that defines the output schema.
- Scripts are user-authored and stored as files that the client can access at runtime.
- The client provides a way to specify the script to execute.
- The REPL exits on EOF or `exit()` and does not persist history between sessions.

## Clarifications

### Session 2026-02-08

- Q: How should `nixstasis script test` failures be handled? → A: Print error details and exit non-zero without pretty-printing output.

- Q: What is the timing requirement for sending aggregated command results? → A: Within 1 second after the last command finishes or times out.

- Q: How should duplicate command_id values be handled in the same batch? → A: Ignore later duplicates and return FAILED with reason duplicate_command_id.

- Q: Should heartbeat commands execute in parallel or sequentially? → A: Parallel, aggregate results.

- Q: How should the client return server-queued command results after a heartbeat? → A: Send a single aggregated command-results API call immediately after processing the full command batch (parallel execution allowed, results gathered at the end).

- Q: What format should `nixstasis script test` use for pretty-printed output? → A: YAML.

## Dependencies

- Documentation or guidance exists for the `stary` file format and expected schema declaration.
