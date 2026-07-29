# Command Policies

Command policies let operators grant Stary `exec_cmd` access without changing the client default of deny-all.

## Manage entries and categories

Open **Scripts → Command Policies**.

- Command entries map one lowercase command name to one absolute executable path.
- Categories are tags on entries; they help assign groups of manual commands.
- Catalog commands are server-curated commands that resolve per device from the latest inventory snapshot.
- Catalog categories select every active catalog command tagged with that catalog category.
- Disabled manual entries and inactive catalog commands are excluded from future policy resolution.
- Duplicate paths are allowed under different command names, but a resolved policy cannot contain conflicting paths for the same name.

## Assign policy to devices

Use the **Device Assignments** section:

1. Select approved devices.
2. Select manual command entries, manual categories, catalog commands, and/or catalog categories.
3. Preview the resolved policy and per-device catalog compatibility.
4. Confirm only when the preview has no manual conflicts and all selected catalog commands are compatible for the selected devices.

The server queues an `apply_command_policy` command through the existing heartbeat command pipeline. Catalog-backed selections still deliver absolute command paths in that payload; package names and inventory evidence are used only to decide whether the server can safely resolve those paths. Large payloads use the existing command-payload reference endpoint.

## Revoke and retry

- **Retry/resend** requeues the same assignment payload.
- **Revoke all** queues a higher-revision empty policy for the device; empty policy means deny all.
- Failed and unsupported clients remain visible in assignment status. Last acknowledged client policy remains active until a new policy is successfully applied.

## Troubleshooting

- `pending/offline`: the device has not polled or reported a result yet.
- `unsupported`: the client does not understand `apply_command_policy`; upgrade the client.
- `stale_inventory`: the selected device has not reported a current catalog inventory snapshot.
- `unsupported_os`: the server has no package mapping for the device OS family.
- `missing_package`: the package that provides a catalog command is not installed; install it manually and wait for the next inventory snapshot.
- `conflict`: catalog evidence reports a different command path than the server-owned mapping, or the client rejected policy ordering/content; resolve the mismatch before confirming.
- `supported` or `package_installed`: the server has partial positive evidence but not a resolved executable path; wait for command-path inventory before confirming.
- `persistence_failed`: the client could not durably write the server policy; inspect client filesystem permissions for `/etc/nixstasis/command-policy.json` or `NIXSTASIS_COMMAND_POLICY_PATH`.
