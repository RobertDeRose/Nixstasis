# CLI Contracts: Stary Script Support

## Overview
This feature adds a `script` subcommand with script management and developer tooling.

## Commands

### `nixstasis script list`
- **Purpose**: List available `stary` scripts.
- **Output**: Table or JSON list including script name, path, and version (if available).
- **Error cases**: Missing scripts directory, invalid front-matter.

### `nixstasis script install <path>`
- **Purpose**: Install a `stary` script from a file path into the client scripts directory.
- **Behavior**:
  - Validates front-matter and schema before install.
  - Fails if a script with the same name already exists unless `--force` is provided.
- **Output**: Installed script name and target path.

### `nixstasis script remove <name>`
- **Purpose**: Remove a previously installed `stary` script by name.
- **Behavior**:
  - Removes the script file and any related metadata.
- **Output**: Confirmation of removal.

### `nixstasis script test <path>`
- **Purpose**: Execute a `stary` script by file path and print YAML output.
- **Behavior**:
  - Runs the script, validates output against schema, and prints YAML.
  - On failure, prints error details and exits non-zero.
- **Output**: YAML-formatted script output on success.

### `nixstasis script repl`
- **Purpose**: Start an interactive Starlark REPL with builtins available.
- **Behavior**:
  - Provides access to builtins such as `pub_and_get` and `exec_cmd`.
  - Exits on EOF or `exit()`.

## Notes
No external HTTP API contracts are introduced by this feature.
