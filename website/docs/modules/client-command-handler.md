# Client Command Handler

Runs the commands the server sends back in heartbeat responses, and reports how each one went. This is the full list
of commands a device understands.

## Owns

- `packages/client/internal/commands/handler.go`: the `Handler` and its command dispatch, and `fs.go` for script file
  operations.
- The persisted server command policy, through `packages/client/internal/commandpolicy/store.go`.
- The in-memory SSH authority for browser terminals, through `packages/client/internal/sshauth/`.

## Entry points

- `ExecuteBatch` runs one heartbeat's commands and returns their results. The poll loop sends them with
  [Client Transport](client-transport.md).
- `NewHandler` and the `NewHandlerWith…` constructors add SSH authorization, runtime configuration, and the policy
  store.

| Command                | Effect                                                                                                                                                                  |
|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `list_scripts`         | Reports installed scripts.                                                                                                                                              |
| `install_script`       | Validates a Stary script and installs it into `scripts.dir`.                                                                                                            |
| `remove_script`        | Removes an installed script.                                                                                                                                            |
| `run_script`           | Runs Stary test content through [Client Starlark Runtime](client-starlark-runtime.md) without installing it. Content type `text/x-stary`.                               |
| `ssh_authorize`        | Validates the versioned payload, target user, session binding, TTL, and public key, then stores the key in the in-memory SSH authority.                                 |
| `ssh_revoke`           | Removes the matching session's key; succeeds if it is already gone, so it is safe to repeat.                                                                            |
| `apply_command_policy` | Replaces the effective `exec_cmd` command map; succeeds only after the runtime configuration is updated and the policy is written durably outside the script directory. |

Unknown command types return a failed result.

## Boundaries

- **Concurrency:** commands that change files, keys, or policy (`install_script`, `remove_script`, `run_script`,
  `ssh_authorize`, `ssh_revoke`, and `apply_command_policy`) run one at a time; other commands run up to eight at once.
  Each command has a five-second timeout.
- **Batches:** results are matched to commands by ID. A repeated command ID in one batch is ignored after its first
  occurrence and reported as failed with `duplicate_command_id`.
- **Deferred payloads:** the poll loop fetches payloads sent by reference before calling the handler. A missing or
  invalid payload becomes a failed result, and the handler never runs partial content.
- **Command policy:** the local `runtime.exec_commands` applies only until the server delivers a policy. From then on,
  the server's policy is used instead. Catalog-backed and manual policies share the same payload: a
  version, a revision, and a map from command name to absolute path.
- **Browser terminal keys** stay in memory and are never written to disk. `sshd` reads them through the hidden
  `nixstasis ssh-authorized-keys` command; see [Runtime Boundaries](../runtime-boundaries.md).
- **Script locations:** installed scripts go in `scripts.dir`, by default `/var/lib/nixstasis/scripts`, owned by the
  service user. Packaged scripts under `/usr/libexec/nixstasis/scripts` stay root-owned and read-only but are still
  discovered.
