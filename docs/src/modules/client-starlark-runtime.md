# Client Starlark Runtime

## Language

- Go.

## Runtime Context

- Client dynamic script execution boundary.

## Purpose

- Parses, validates, installs, discovers, executes, and reports Stary/Starlark telemetry scripts.

## Key Files

- `packages/client/internal/script/runtime.go`
- `packages/client/internal/script/executor.go`
- `packages/client/internal/script/types.go`
- `packages/client/internal/script/discovery.go`
- `packages/client/internal/script/validator.go`
- `packages/client/internal/script/report.go`
- `packages/client/internal/script/repl.go`
- `packages/client/internal/script/format.go`
- `packages/client/internal/script/version.go`
- `packages/client/internal/script/builtins_exec.go`
- `packages/client/internal/script/builtins_mqtt.go`
- `packages/client/cmd/nixstasis/install_script.go`
- `docs/src/features/starlark-script-system/design.md`
- `packages/client/README.md`

## Public Interfaces

- Types:
  - `Runtime`
  - `RuntimeConfig`
  - `Executor`
  - `ScriptInfo`
  - `ScriptResult`
  - `ScriptError`
  - `ScriptWarning`
  - `FrontMatter`
- Functions and methods:
  - `NewRuntime`
  - `(*Runtime).Builtins`
  - `(*Runtime).Close`
  - `(*Runtime).Execute`
  - `NewExecutor`
  - `(*Executor).ExecuteScripts`
  - `DiscoverScripts`
  - `SelectLatestScripts`
  - `ParseStaryFile`
  - `ParseStaryContent`
  - `CompileSchema`
  - `ValidateOutput`
  - `ToReport`
  - `DefaultInstallDir`
  - `InstallFilename`
  - `ParseVersionNumber`
  - `MaxVersion`

## Dependencies

### Internal

- `internal/telemetry`
- CLI commands under `cmd/nixstasis/script*`.

### External

- `go.starlark.net/starlark`
- `go.starlark.net/syntax`
- `go.starlark.net/lib/json`
- `github.com/eclipse/paho.mqtt.golang`
- `github.com/santhosh-tekuri/jsonschema/v5`

## Client-Server Interaction Details

- Script outputs are transformed into telemetry reports during `pollOnce` and sent inside the heartbeat `telemetry` object.
- Server-issued commands can install/remove scripts and can replace the effective `exec_cmd` allowlist through `internal/commands.Handler`.
- `.stary` scripts contain YAML front matter plus a Starlark body. Validation
  compiles front matter schemas before installed scripts can contribute
  telemetry.
- Script execution is bounded: executions have a five-second timeout and emit a
  slow-script warning after three seconds.
- When a persisted server command policy exists, it overrides locally configured `runtime.exec_commands`; local config is fallback only before the first successful server policy write.
- Catalog-backed command policies use the same persisted `apply_command_policy` payload as manual policies: a version, revision, and command-name to absolute-path map.
- Package names, catalog IDs, and command inventory evidence are not runtime authority. They are server-side compatibility inputs only and do not expand `exec_cmd` permissions unless the server later delivers an absolute-path policy.
- `script test` prints normalized YAML output on success and exits non-zero
  without telemetry output when validation or execution fails.
- Server command batches are correlated by command ID. Duplicate command IDs in a
  batch are ignored after the first occurrence and reported as failed with a
  `duplicate_command_id` reason.

Traceable references:

- `packages/client/internal/script/runtime.go:20-179`
- `packages/client/internal/script/executor.go:13-133`
- `packages/client/cmd/nixstasis/poll.go:105-126`
- `packages/client/cmd/nixstasis/install_script.go:16-77`
