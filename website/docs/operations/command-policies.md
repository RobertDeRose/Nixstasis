# Command Policies

By default, a device's Stary scripts cannot run any command with `exec_cmd`. Command policies are how you allow
specific commands on specific devices.

## Manage entries and categories

Open **Scripts → Command Policies**. There are two kinds of command:

- **Manual entries** map one lowercase command name to one absolute path, such as `uptime` to `/usr/bin/uptime`. You
  can tag entries with **categories** to assign several at once.
- **Catalog commands** are curated on the server by package. Instead of a fixed path, the server works out each
  device's path from the packages and commands the device reports. **Catalog categories** select every active catalog
  command with that tag.

A disabled manual entry, or an inactive catalog command, is left out of future policies. The same path can appear under
different command names, but one command name cannot resolve to two different paths in the same policy.

## Assign a policy to devices

In the **Device Assignments** section:

1. Select approved devices.
2. Select any mix of manual entries, manual categories, catalog commands, and catalog categories.
3. Preview the result. The preview shows the commands each device would get, and whether each catalog command can be
   resolved on each device. Changing the selection afterwards discards the preview, so preview again before
   confirming.
4. Confirm once the preview shows no conflicts and every catalog command works on every selected device.

The server sends the policy to each device as an `apply_command_policy` command on its next heartbeat. Even catalog
commands arrive on the device as absolute paths: package names and inventory reports only help the server decide
whether it can resolve a path safely. Large policies are fetched separately, like any other large command payload.

A selection can resolve to at most 2,500 distinct commands, or 10,000 policy source rows. Beyond that, the server
refuses the selection rather than silently dropping part of a category; narrow it down and preview again.

## Revoke and retry

- **Retry/resend** sends the same assignment again.
- **Revoke all** sends the device a newer, empty policy. An empty policy allows nothing.

Devices that failed, or whose client is too old, stay visible in the assignment status. A device keeps using the last
policy it confirmed until a new one is applied successfully.

## Troubleshooting

| Status                             | What it means                                                                                                        | What to do                                                                                                 |
|------------------------------------|----------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| `pending/offline`                  | The device has not checked in or reported a result yet.                                                              | Wait for its next heartbeat.                                                                               |
| `unsupported`                      | The client does not understand `apply_command_policy`.                                                               | Upgrade the client.                                                                                        |
| `stale inventory`                  | The device has not sent a recent inventory report.                                                                   | Wait for its next report.                                                                                  |
| `unsupported os`                   | The server has no package mapping for the device's OS family.                                                        | Use manual entries for that device instead.                                                                |
| `missing package`                  | The package that provides the catalog command is not installed.                                                      | Install it yourself, then wait for the next inventory report.                                              |
| `conflict`                         | The device reports a different path than the server's mapping, or the client rejected the policy's order or content. | Resolve the mismatch before confirming.                                                                    |
| `supported` or `package installed` | The server knows the package is there, but not yet the command's path.                                               | Wait for the device to report the command path.                                                            |
| `persistence_failed`               | The client could not save the policy to disk.                                                                        | Check permissions on `/etc/nixstasis/command-policy.json`, or the path in `NIXSTASIS_COMMAND_POLICY_PATH`. |
