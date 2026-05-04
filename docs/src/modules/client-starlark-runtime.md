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
- `specs/007-starlark-script-system/spec.md`
- `specs/007-starlark-script-system/contracts/cli.md`

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
- Server-issued commands can install or remove scripts through `internal/commands.Handler`.

Traceable references:
- `packages/client/internal/script/runtime.go:20-179`
- `packages/client/internal/script/executor.go:13-133`
- `packages/client/cmd/nixstasis/poll.go:105-126`
- `packages/client/cmd/nixstasis/install_script.go:16-77`
