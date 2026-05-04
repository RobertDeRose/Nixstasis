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

- `POST /api/v1/devices/register` calls `Devices.register_device/1`.
- `POST /api/v1/devices/:device_id/heartbeat` calls `Monitoring.heartbeat/2`, which updates last seen and returns pending commands.
- `POST /api/v1/devices/:device_id/command_results` calls `Devices.acknowledge_command_results/2`.
- `GET /api/v1/devices/:device_id/command_payloads/:ref` calls `Devices.get_command_payload/2`.
- Device detail LiveView queues `ssh_authorize` commands before terminal session startup.

Traceable references:
- `packages/server/lib/nixstasis/devices.ex:1-360`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex:31-65`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex:7-27`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:6-39`
- `packages/server/lib/nixstasis_web/live/device_live/show.ex:57-80`
