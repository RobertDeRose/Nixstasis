# Implementation Plan: Stary Script Support

**Branch**: `007-starlark-script-system` | **Date**: February 8, 2026 | **Spec**: specs/007-starlark-script-system/spec.md
**Input**: Feature specification from `/specs/007-starlark-script-system/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command.
See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Replace the Go client plugin system with `stary` Starlark scripts that declare an output schema in YAML front-matter. Provide built-in Starlark functions for MQTT request/response and for executing OS commands with safety controls. Add CLI subcommands under `nixstasis script` to list, install, remove, and test scripts, plus a Starlark REPL with builtins. The `nixstasis script test` command prints script output as YAML and exits non-zero with error details on failure. Script output must be validated against declared schema, warnings emitted for slow scripts (>3s), and errors returned for execution, validation, or timeout failures (>5s). Add heartbeat command handling: server can include queued commands in poll responses; client executes them in parallel when possible, ignores duplicate command_id values in the same batch, and sends a single aggregated command-results call within 1 second of the last command finishing. Command results are sent via a dedicated transport call (new endpoint or existing client method) immediately after processing the heartbeat command batch.

## Technical Context

**Language/Version**: Go 1.25.4 (client)
**Primary Dependencies**: Cobra/Viper (existing), Starlark (go.starlark.net), YAML v3 (existing), MQTT client (paho.mqtt.golang), JSON Schema validator (github.com/santhosh-tekuri/jsonschema/v5)
**Storage**: Files on disk for `stary` scripts and schema front-matter
**Testing**: Go `testing` package with Given/When/Then style naming for behavior, plus targeted unit tests for parsing, validation, and MQTT response filtering
**Target Platform**: Linux client (Debian package)
**Project Type**: Single CLI project under `packages/client`
**Performance Goals**: Script execution completes within 5 seconds; warning at >3 seconds
**Constraints**: Timeouts for script execution and MQTT response (5 seconds); command execution must be restricted by user and blacklist; heartbeat commands must be processed within 5 seconds each with aggregated results reported within 1 second after completion; duplicate command_id values are treated as failures.
**Transport**: Poll response can include commands; client sends aggregated command results via a dedicated API call (defined in transport client).
**Scale/Scope**: Expect tens of scripts per device; scripts executed per poll cycle

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Quality & Simplicity**: Pass. Plan keeps a single scripting subsystem and validates outputs with clear error handling.
- **Behavior-Driven API Testing**: Pass. CLI and telemetry behaviors will be tested with Given/When/Then naming.
- **Targeted Unit Testing**: Pass. Parsing, schema validation, MQTT filtering, and timeout behavior will have unit tests.
- **User Experience First**: Pass. Clear errors, warnings, and predictable outputs improve operator UX.
- **Branding**: Not applicable (CLI only).
- **Performance Compliance**: Pass. Timeouts and warnings are explicit requirements.
- **Technology Standards**: Exception. Constitution targets Elixir for server; client is Go per repository standards in `/packages`. This plan stays in Go to align with existing client code.

## Project Structure

### Documentation (this feature)

```text
specs/007-starlark-script-system/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
packages/
├── client/
│   ├── cmd/nixstasis/            # CLI commands
│   └── internal/
│       ├── config/
│       ├── plugin/               # Will be replaced by stary scripting subsystem
│       ├── transport/
│       └── ...
└── server/
```

**Structure Decision**: Single CLI project under `packages/client` with new scripting and command logic added under `internal/` and `cmd/nixstasis`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| Technology standard (Go vs Elixir) | Client is already implemented in Go and must embed Starlark | Rewriting client in Elixir is out of scope for this feature |
