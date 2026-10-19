# Starlark Script System

The client runs `.stary` telemetry scripts: YAML front matter, Starlark code, and a schema for the output. It can
find, install, remove, list, and test scripts, offers a REPL, talks MQTT, runs allowed commands within limits, and
reports the results. The original plan is in the [design record](design.md).

## What changed for users

Integrators can pick a script by path or by name, check its output locally, and see exactly which fields fail the
schema. The same runtime runs scripts during polling. If two scripts share a name, you have to use the path. A script
that runs away is stopped by a time limit and by a limit on interpreter steps.

## How it fits in

The built-in runtime converts Starlark values into Go data, checks the output before it goes into a heartbeat, and
offers only a small set of limited builtins. `exec_cmd` allows nothing by default, and follows the current command
policy.

## Running it

Time limits, the step limit, schema checks, a cleaned-up environment for commands, permission checks, and matching
every command to its result stop a misbehaving script from doing much harm or reaching much of the host.

## Differences from the design

Later work added server-delivered command policies that are saved on the device, a stricter cleanup of the command
environment, and one shared runtime per poll.

## Not included

- Writing and deploying scripts from the server is a separate feature, the
  [Stary Script Workbench](../server-stary-script-workbench/index.md).
- Scripts never get unrestricted shell access, and cannot skip their output schema.

## Tests

- `packages/client/internal/script/format_test.go` and `validation_test.go`: parsing, front matter, and output schema
  checks for valid and invalid scripts.
- `packages/client/internal/script/runtime_test.go` and `executor_test.go`: converting Starlark values to Go, time
  limits, and stopping runaway scripts.
- `packages/client/internal/script/discovery_test.go`: finding scripts, and choosing between scripts with the same name.
- `packages/client/internal/script/builtins_mqtt_test.go`, `builtins_exec_test.go`, and the
  `builtins_read_file*_test.go` files: the builtins and their limits, including `exec_cmd` allowing nothing by default.
- `packages/client/internal/script/report_test.go`: reporting results.
- `packages/client/cmd/nixstasis/scripts_test.go`, `test_script_test.go`, `repl_test.go`, and `poll_test.go`: installing,
  removing, listing, testing, the REPL, and polling.

## Related pages

- [Client Starlark Runtime](../../modules/client-starlark-runtime.md)
- [Client Command Handler](../../modules/client-command-handler.md)
- [Client CLI](../../modules/client-cli.md)
- `packages/client/README.md`
