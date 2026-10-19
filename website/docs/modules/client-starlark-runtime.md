# Client Starlark Runtime

The client's Stary script engine. It parses, checks, installs, finds, and runs `.stary` scripts, and turns what they
return into heartbeat telemetry. The script format, the execution limits, and the builtins are all defined here.

## Owns

- `packages/client/internal/script/`: parsing and validation (`format.go`, `validator.go`), discovery and versioning
  (`discovery.go`, `version.go`), execution (`runtime.go`, `executor.go`, `report.go`), the REPL (`repl.go`), and the
  builtins (`builtins_exec.go`, `builtins_read_file.go`, `builtins_mqtt.go`).

## Entry points

- `ParseStaryFile` and `ParseStaryContent` parse a script; `CompileSchema` and `ValidateOutput` check its schema and
  results.
- `DiscoverScripts` and `SelectLatestScripts` find installed scripts and choose the newest version of each.
- `NewRuntime` and `NewExecutor` run scripts; `ToReport` converts their results into telemetry fields.
- The poll loop runs every installed script on each heartbeat; [Client Command Handler](client-command-handler.md) runs
  server-delivered `run_script` content through the same runtime without installing it.
- The `nixstasis script` commands in [Client CLI](client-cli.md) install, list, remove, test, and explore scripts.

## Boundaries

### Script format

A `.stary` file is YAML front matter followed by a Starlark body that defines a callable `main()`. Its non-null result
must be a dictionary. Front-matter schemas are compiled before a script can contribute telemetry, and source is limited
to 1 MiB before parsing, for files and server-delivered content alike.

### Execution limits

- Each run has a five-second wall-clock timeout and a 1,000,000-step Starlark computation budget; exceeding either is
  a normal execution error. A slow-script warning is logged after three seconds.
- The step budget limits interpreter work, not memory, so builtins and result conversion enforce their own size limits.
- Converting results to Go rejects cycles and limits nesting to 64 levels, totals to 10,000 values and keys, strings and
  keys to 256 KiB, and the whole result to about 1 MiB.

### Builtins

- **`exec_cmd`** runs nothing unless it is allowed. A command name runs only if the current command policy maps it to
  an absolute executable path. If the script passes arguments, they must exactly match an entry for that path in the
  device's own `runtime.exec_command_args`, which the server's policy cannot add to. Combined stdout and stderr are capped at 256 KiB; a command that writes
  more is stopped and the call fails. Commands can run as a restricted UID and GID.
- **`read_file`** reads only exact paths listed in the client-local `runtime.read_files`, at most 64 KiB per read, and
  always refuses paths under `/etc/nixstasis` and `/run/nixstasis`. It refuses symlinks anywhere in the path and
  anything that is not a regular file, and it opens files in a way that stops a path from being swapped out, or a
  FIFO used, to get around those checks. The
  shipped command map has no generic `cat`.
- **`pub_and_get`** publishes to MQTT and waits for a reply. Allowlist entries may use `+` and `#`, but scripts must
  name concrete topics, and wildcard entries never match `$`-prefixed system topics. Replies over 1 MiB fail the call.
- **`json`** encodes and decodes JSON.

### Command policy

The command policy that `exec_cmd` enforces comes from the server once one has been delivered, and from the local
`runtime.exec_commands` before that; see [Client Command Handler](client-command-handler.md). Package names, catalog
IDs, and inventory evidence never grant command access.
