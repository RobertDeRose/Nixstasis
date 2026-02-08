# Data Model: Stary Script Support

## Entities

### StaryScript
- **name**: Human-readable script name (from front-matter)
- **version**: Optional version identifier
- **path**: File path to the `stary` file
- **schema**: JSON Schema definition (YAML front-matter)
- **body**: Starlark source code

### ScriptExecutionResult
- **script_name**: Name of the script
- **status**: `success` | `error` | `timeout`
- **duration_ms**: Execution duration in milliseconds
- **output**: Script output object (present on success)
- **error**: ScriptError (present on error/timeout)
- **warnings**: List of ScriptWarning (present when duration > 3 seconds)

### ScriptError
- **type**: `syntax` | `execution` | `validation` | `timeout` | `io`
- **message**: Human-readable error message
- **details**: Optional structured details (e.g., validation failures)

### ScriptWarning
- **type**: `slow_execution`
- **message**: Warning message
- **duration_ms**: Duration that triggered the warning

### TelemetryPayload
- **device**: Device identity and status (existing)
- **plugins**: Map of script reports keyed by script name
- **meta**: Poll metadata, including errors list

## Relationships

- A `StaryScript` produces a `ScriptExecutionResult` per poll.
- `TelemetryPayload.plugins` stores `ScriptExecutionResult` data keyed by script name.
- `ScriptExecutionResult` may reference `ScriptError` and `ScriptWarning` entities.

## Validation Rules

- Output must satisfy the JSON Schema from `StaryScript.schema`.
- Responses for MQTT `pub_and_get` must satisfy `accept` filters before being returned to scripts.
- Script execution exceeding 5 seconds is a `timeout` error.
