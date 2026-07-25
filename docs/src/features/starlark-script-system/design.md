<!-- workflow-migration:legacy-markdown-to-beads -->

# Starlark Script System

## Feature Name

`starlark-script-system`

## Goal

Provide a Starlark-based client extension system using `stary` files with YAML
front matter and declared output schemas.

## Users

- Device integrators extending telemetry and command behavior.
- Developers testing scripts locally before enabling them in polling flows.

## Requirements

- Accept user-authored `stary` files with YAML front matter and Starlark body.
- Require front matter to declare an output schema.
- Validate script output against the declared schema with field-level errors.
- Allow scripts to be selected by path or unique name; conflicting names require path selection.
- Support install, remove, list, test, and REPL workflows from the CLI.
- Provide Starlark builtins including MQTT-style `pub_and_get` and deny-by-default command execution.
- Execute heartbeat command batches and send aggregated command results back to the server.
- Correlate command results by `command_id` and handle duplicate IDs deterministically.
- Time out scripts and commands that exceed configured execution windows.

## Proposed Design

The client embeds a Starlark runtime with a parser for `stary` files, schema
validation, execution result reporting, and CLI helpers for local development.
Command execution is restricted and documented as deny-by-default with an
allowlist model for executable paths.

Durable CLI usage belongs in `packages/client/README.md`; runtime architecture
belongs in `docs/src/modules/client-starlark-runtime.md` and
`docs/src/modules/client-command-handler.md`.

## Edge Cases

- Missing or invalid YAML front matter.
- YAML front matter without a script body.
- Output missing required schema fields.
- Duplicate script names.
- Long-running scripts or commands.
- Duplicate `command_id` values in a heartbeat batch.

## Validation

- `nixstasis script test <path>` prints YAML for valid output and exits non-zero on parse/execution/validation failures.
- REPL starts with supported builtins available.
- Command batches run with timeout and duplicate handling.
- Aggregated command results are sent promptly after batch completion.
