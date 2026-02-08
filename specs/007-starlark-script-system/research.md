# Research: Stary Script Support

## Decision 1: Starlark implementation
- **Decision**: Use `go.starlark.net` as the embedded Starlark interpreter.
- **Rationale**: Pure Go, idiomatic embedding API, and standard for Starlark on Go.
- **Alternatives considered**: Custom DSL or invoking external binaries (rejected due to complexity and inconsistent outputs).

## Decision 2: Stary file format
- **Decision**: `stary` files use YAML front-matter separated by `---` from the Starlark body. Front-matter includes `name`, `version` (optional), and `schema` (required).
- **Rationale**: Front-matter is common and easy to parse; separating schema from code keeps validation explicit.
- **Alternatives considered**: JSON-only headers or sidecar schema files (rejected due to added complexity and file management overhead).

## Decision 3: Output schema validation
- **Decision**: Use JSON Schema expressed in YAML front-matter and validate script output using `github.com/santhosh-tekuri/jsonschema/v5`.
- **Rationale**: JSON Schema is expressive and widely understood; YAML serialization keeps authoring simple.
- **Alternatives considered**: Custom type-map schema (rejected due to limited expressiveness and future growth constraints).

## Decision 4: MQTT request/response helper
- **Decision**: Implement `pub_and_get(topic, msg, reply_topic=None, accept=None)` as a built-in Starlark function that subscribes to the reply topic (defaults to `topic`), publishes `msg`, and returns the first response that matches `accept` within 5 seconds.
- **Rationale**: Matches the requested Bash flow while adding reply topic support and filtering.
- **Alternatives considered**: Separate publish and subscribe functions (rejected due to additional script complexity).

## Decision 5: Accept filter semantics
- **Decision**: `accept` is a map of key/value pairs that must all match the response payload (parsed as JSON object). Responses that do not contain all required keys or values are ignored.
- **Rationale**: Clear and testable filtering; aligns with user request.
- **Alternatives considered**: Partial match or regex matching (rejected due to ambiguity and increased complexity).

## Decision 6: Script execution limits and errors
- **Decision**: Enforce a 5-second execution timeout per script; add warnings when execution exceeds 3 seconds. Errors include script name and reason (syntax, execution, validation, timeout).
- **Rationale**: Provides predictable performance and actionable operator feedback.
- **Alternatives considered**: No warnings or longer timeouts (rejected due to performance and UX requirements).

## Decision 7: OS command execution safety
- **Decision**: Expose a built-in function that executes OS commands as a restricted user (configurable) and denies commands matching a blacklist (e.g., `rm`, `mkfs`/`mkfs.*`).
- **Rationale**: Defense-in-depth even if the OS user is already restricted.
- **Alternatives considered**: Allow all commands (rejected due to security risk).
