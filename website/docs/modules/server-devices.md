# Server Devices

The `Nixstasis.Devices` context: device identity, registration, approval, groups, the queue of commands waiting for
each device, and remote access. The rules for remote-access leases are described here.

## Owns

- `Nixstasis.Devices` in `packages/server/lib/nixstasis/devices.ex` and the resources and helpers under
  `packages/server/lib/nixstasis/devices/`.
- Device registration, runtime tokens, and device authentication.
- Operator approval and rejection, and device groups with their memberships.
- The pending-command queue and deferred command payloads.
- Remote-access leases, FRPS device credentials (`frps_token.ex`), SSH host keys, and ephemeral terminal keys
  (`ssh_key_manager.ex`).

## Entry points

- **Registration:** `register_runtime_device/1`, called by both the `/api/v1` and generated registration routes.
  Initial enrollment claims a client-prepared proof hash. An approved exchange atomically verifies the current proof,
  updates device-owned attributes, and stores the client's replacement hash. Retrying with the committed replacement
  returns the same runtime token without changing anything. Registration never overwrites operator-owned approval or
  remote-access settings.
- **Authentication:** `authenticate_device/2` checks the runtime token sent as `Authorization: Bearer`.
- **Fleet queries:** `list_devices/1` applies search, `authorized_device_ids`, `group_id`, sorting, and `limit` in SQL.
  Search covers product name, MAC address, account number, and IPv4 address, and `:select` limits the loaded fields.
- **Commands:** `queue_command/2`, `queue_command_policy_assignment/2`, and `queue_terminal_revoke/2` enqueue work;
  `pop_pending_commands/1` hands it to a heartbeat; `acknowledge_command_results/2` records results; and
  `get_command_payload/2` serves large payloads by reference.
- **Remote access:** `open_remote_access_lease/2`, `close_remote_access_lease/2`, `set_remote_access/2`, and
  `set_remote_access_profile/2`.
- **Groups:** `create_device_group/2` and the related update, archive, restore, and membership functions.

## Boundaries

- **Remote-access leases:** opening a remote-access session creates a durable lease with a UUID, owner kind and ID,
  profile, expiry, and audit subject. The remote-access fields on a device only mirror the lease currently in effect;
  changing them directly cannot grant or revoke access.
  - Provisioning leases take precedence over browser and direct leases. Within a class the newest lease wins, with the
    UUID breaking ties, and closing it restores the next eligible lease.
  - FRPS credentials carry the selected lease's identity and expire with it. Heartbeats advertise
    `remote_access_lease_id` and `remote_access_expires_at_ms`, and FRPS checks that exact lease before allowing a login
    or proxy ([Gateway FRP](gateway-frp.md)).
  - `set_remote_access(device, false)` withdraws every lease for the device; session and delivery cleanup close only
    their own lease. Changing the profile saves a preference for future leases without altering an open one.
  - On restart the supervisor restores the original leases and timers; it never synthesizes leases from device flags.
  - Lease updates run under the device row lock, so a concurrent heartbeat or profile change cannot overwrite them.
- **Terminal sessions:** the session reference is created before `ssh_authorize` is queued, and the browser token
  activates only after the device reports that command succeeded. On close, expiry, or failure the server queues an
  `ssh_revoke`, which is safe to repeat. The wire format is in
  [API & Runtime Contracts](../reference/contracts.md#browser-terminal-ssh-authorization-contract).
- **Groups:** every change needs a trusted operator ID, so in production a request without a trusted subject or email
  is refused. Unscoped managers own group metadata; scoped managers change memberships only for devices in their scope.
  Changes publish audit events after commit and a payload-free `:device_groups_changed` event for the Devices LiveView.
  Group names are unique regardless of case and stay reserved while archived. Operator workflows are in
  [Device Groups](../operations/device-groups.md).
- **Heartbeats** are orchestrated by [Server Monitoring](server-monitoring.md), which calls into this context.
- Telemetry and schema data stay dynamic JSON so product-specific Stary scripts can evolve without schema changes.
