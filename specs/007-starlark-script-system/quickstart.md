# Quickstart: Stary Script Support

## Create a Stary Script

1. Create a file with `.stary` extension.
2. Add YAML front-matter with `name` and `schema`, then the Starlark body.

Example:

```text
---
name: device_info
schema:
  type: object
  properties:
    hostname:
      type: string
    uptime_seconds:
      type: number
  required: [hostname, uptime_seconds]
---

def main():
    return {"hostname": "example", "uptime_seconds": 123}
```

## Install a Script

```bash
nixstasis script install ./device_info.stary
```

## List Scripts

```bash
nixstasis script list
```

## Remove a Script

```bash
nixstasis script remove device_info
```

## Test a Script

```bash
nixstasis script test ./device_info.stary
```

The output is printed as YAML. Failures print error details and exit non-zero.

## Start the REPL

```bash
nixstasis script repl
```

Use builtins like `pub_and_get` and `exec_cmd` interactively. Exit with `Ctrl-D` or `exit()`.

## Using MQTT in a Script

The built-in function `pub_and_get` publishes a message and waits for a response:

```text
response = pub_and_get("sensors/request", "{\"type\": \"get\"}")
```

## Executing OS Commands

Use the built-in `exec_cmd` to run allowed commands:

```text
hostname = exec_cmd("hostname")
```

Blocked commands (e.g., `rm`, `mkfs`) return an error.

## Execution Behavior

- Script output is validated against the declared schema.
- Scripts taking longer than 3 seconds add a warning.
- Scripts exceeding 5 seconds return a timeout error.
