# Command Policies

Command policies let operators grant Stary `exec_cmd` access without changing the client default of deny-all.

## Manage entries and categories

Open **Scripts → Command Policies**.

- Command entries map one lowercase command name to one absolute executable path.
- Categories are tags on entries; they help assign groups of commands.
- Disabled entries are excluded from future policy resolution.
- Duplicate paths are allowed under different command names, but a resolved policy cannot contain conflicting paths for the same name.

## Assign policy to devices

Use the **Device Assignments** section:

1. Select approved devices.
2. Select command entries and/or categories.
3. Preview the resolved policy.
4. Confirm only when the preview has no conflicts.

The server queues an `apply_command_policy` command through the existing heartbeat command pipeline. Large payloads use the existing command-payload reference endpoint.

## Revoke and retry

- **Retry/resend** requeues the same assignment payload.
- **Revoke all** queues a higher-revision empty policy for the device; empty policy means deny all.
- Failed and unsupported clients remain visible in assignment status. Last acknowledged client policy remains active until a new policy is successfully applied.

## Troubleshooting

- `pending/offline`: the device has not polled or reported a result yet.
- `unsupported`: the client does not understand `apply_command_policy`; upgrade the client.
- `conflict` or `stale`: the client rejected the policy ordering/content; retry with the latest assignment.
- `persistence_failed`: the client could not durably write the server policy; inspect client filesystem permissions for `/etc/nixstasis/command-policy.json` or `NIXSTASIS_COMMAND_POLICY_PATH`.
