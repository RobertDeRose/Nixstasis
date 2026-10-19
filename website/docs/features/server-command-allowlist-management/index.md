# Server Command Allowlist Management

Operators can define which commands device scripts may run. Each entry maps a command name to an absolute path, entries
can be grouped into categories, and you can preview the resulting policy for each device before sending it. Policies go
out as versioned `apply_command_policy` commands over the usual device command channel. The original plan is in the
[design record](design.md).

## What changed for users

The Command Policies page handles entries, categories, assigning policies to devices, previews, conflicts, retries,
revoking, and delivery status. Operators limited to some devices only see, and can only change, those devices.

## How it fits in

The server keeps the record of what each device should be allowed to run, with an audit trail. The client saves
each policy to disk, only ever moves to a newer revision, and is where `exec_cmd` is actually enforced; by default it
allows nothing. Confirmations and failures come back as ordinary command results.

## Running it

Devices that are offline, or whose client is too old, stay visible as pending or failed. Removing an assignment sends
the device a newer replacement policy, and an empty policy allows nothing.

## Differences from the design

Categories are stored as their own records, linked to entries, and a device's policy still adds together everything
assigned to it.

## Not included

- Policies cover whole commands only: no rules about arguments.
- Categories are flat, with no nesting, and there are no automatic device groups.
- There is no CSV export, and no automatic correction when a device drifts from its policy.
- Shell snippets are never allowed, permissions are never guessed from scripts, and the client still enforces every
  policy itself.

## Tests

- `packages/server/test/nixstasis/command_allowlists/command_entry_test.exs` and `category_test.exs`: entries and
  categories.
- `packages/server/test/nixstasis/command_allowlists/policy_resolver_test.exs`: working out each device's policy, and
  conflicts.
- `packages/server/test/nixstasis/command_allowlists/device_policy_assignment_test.exs`: scoped assignment, revisions,
  and revoking.
- `packages/server/test/nixstasis/command_allowlists/policy_delivery_result_test.exs`: delivery confirmations and
  failures.
- `packages/server/test/nixstasis_web/live/command_policy_live_test.exs` and
  `packages/server/test/nixstasis_web/controllers/command_policy_controller_test.exs`: the Command Policies workflows
  and device-scoped permissions.
- `packages/client/internal/commandpolicy/store_test.go`: saving policies, repeated deliveries, out-of-date revisions,
  and conflicts.
- `packages/client/internal/commands/handler_test.go`: receiving policies, and refusing commands they don't allow.

## Related pages

- [Command Policies](../../operations/command-policies.md)
- [API & Runtime Contracts](../../reference/contracts.md#command-policy-contract)
- [Client-Server Interface](../../client-server-interface.md)
- [Data Flow](../../data-flow.md)
- [Client Command Handler](../../modules/client-command-handler.md)
- [Client Starlark Runtime](../../modules/client-starlark-runtime.md)
