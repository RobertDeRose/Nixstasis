# Server Devices

## Language

- Elixir.

## Runtime Context

- Server context and Ash resource layer.

## Purpose

- Manages device registration, listing, approval, remote-access flags, pending command queueing, command delivery, command acknowledgement, command payload retrieval, and SSH terminal process support.

## Key Files

- `packages/server/lib/nixstasis/devices.ex`
- `packages/server/lib/nixstasis/devices/device.ex`
- `packages/server/lib/nixstasis/devices/pending_command.ex`
- `packages/server/lib/nixstasis/devices/schema_validator.ex`
- `packages/server/lib/nixstasis/devices/ssh_key_manager.ex`
- `packages/server/lib/nixstasis/devices/ssh_client.ex`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex`
- `packages/server/lib/nixstasis_web/live/device_live/index.ex`
- `packages/server/lib/nixstasis_web/live/device_live/show.ex`

## Public Interfaces

- Context functions:
  - `Nixstasis.Devices.count_all/0`
  - `Nixstasis.Devices.count_by_status/1`
  - `Nixstasis.Devices.count_pending_approvals/0`
  - `Nixstasis.Devices.register_device/1`
  - `Nixstasis.Devices.update_last_seen/1`
  - `Nixstasis.Devices.list_pending_devices/0`
  - `Nixstasis.Devices.approve_device/1`
  - `Nixstasis.Devices.list_devices/1`
  - `Nixstasis.Devices.requesting_remote_access?/1`
  - `Nixstasis.Devices.approve_devices/1`
  - `Nixstasis.Devices.reject_devices/1`
  - `Nixstasis.Devices.set_remote_access/2`
  - `Nixstasis.Devices.get_device!/1`
  - `Nixstasis.Devices.create_device/1`
  - `Nixstasis.Devices.update_device/2`
  - `Nixstasis.Devices.delete_device/1`
  - `Nixstasis.Devices.change_device/2`
  - `Nixstasis.Devices.queue_command/2`
  - `Nixstasis.Devices.pop_pending_commands/1`
  - `Nixstasis.Devices.acknowledge_command_results/2`
  - `Nixstasis.Devices.get_command_payload/2`
  - `Nixstasis.Devices.online?/1`
- GenServer/process interfaces:
  - `Nixstasis.Devices.SshClient.start_link/1`
  - `Nixstasis.Devices.SshClient.send_data/2`
  - `Nixstasis.Devices.SshClient.ssh_host/1`

## Dependencies

### Internal

- `Nixstasis.Domain`
- `Nixstasis.Repo`
- `Nixstasis.Devices.Device`
- `Nixstasis.Devices.PendingCommand`
- `Nixstasis.Devices.SchemaValidator`

### External

- Ash
- AshPhoenix
- Ecto/PostgreSQL
- Elixir Port for `ssh`
- `ncat` through SSH `ProxyCommand`

## Client-Server Interaction Details

- Device `/api/v1` runtime routes remain bespoke controller routes until strict
  Go client compatibility tests cover authentication, pending/approved
  registration token behavior, heartbeat remote-access directives, command result
  acknowledgement, deferred payload retrieval, and status-code semantics.
- `POST /api/v1/devices/register` calls `Devices.register_public_device/1`.
- `POST /api/v1/devices/:device_id/heartbeat` calls `Monitoring.heartbeat/2`, which updates last seen and returns pending commands.
- `POST /api/v1/devices/:device_id/command_results` calls `Devices.acknowledge_command_results/2`.
- `GET /api/v1/devices/:device_id/command_payloads/:ref` calls `Devices.get_command_payload/2`.
- Terminal session startup creates an opaque session ref **before** queueing
  `ssh_authorize`, so the queued command carries the ref. See
   `packages/server/lib/nixstasis_web/live/device_live/show.ex` lines 171-192 for the full sequencing.
- Terminal authorization commands carry the public key at top level and a dynamic
  JSON payload with `target_user=nixstasis-support`, `ttl_seconds`, and
  `session_ref`. The in-memory `ssh_authorize` payload is the only shape the
  server emits; there is no file-based fallback and no capability gate.
- Browser terminal token activation is gated on an OK `ssh_authorize` command
  result from the device.
- Server queues an `ssh_revoke` command (`content_type:
  application/vnd.nixstasis.ssh-revoke+json;version=1`) on terminal close,
  session expiry, or cleanup paths as a best-effort early invalidation signal.
- Device detail is reached through `/devices/:id`; opening remote-access tabs may
  set `remote_access_requested`, and close/cleanup paths must clear stale remote
  access intent.
- PCP metrics, Cockpit links, and terminal sessions are detail-view concerns and
  should degrade gracefully when FRP, SSH, or device data is unavailable.

## Data Model Notes

- Device records carry stable identity and operational fields such as MAC
  address, product/product name, account number, approval status, schema
  definition, last-seen/last-polled timestamps, metadata, and remote-access
  intent.
- Telemetry and schema data intentionally remain dynamic JSON structures so
  product-specific Stary scripts can evolve without one relational table per
  product payload.
- Detailed historical product requirements live in
  [IoT Device Monitoring](../features/iot-device-monitoring/design.md) and
  [Device Detail Page](../features/device-detail-page/design.md); runtime API
  payloads live in [Client-Server Interface](../client-server-interface.md).

Traceable references:

- `packages/server/lib/nixstasis/devices.ex:1-360`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex:31-65`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex:7-27`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:6-39`
- `packages/server/lib/nixstasis_web/live/device_live/show.ex:57-80`
