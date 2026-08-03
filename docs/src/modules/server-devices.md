# Server Devices

## Language

- Elixir.

## Runtime Context

- Server context and Ash resource layer.

## Purpose

- Manages device registration, listing, approval, manual group organization, remote-access flags, pending command queueing, command delivery, command acknowledgement, command payload retrieval, and SSH terminal process support.

## Key Files

- `packages/server/lib/nixstasis/devices.ex`
- `packages/server/lib/nixstasis/devices/device.ex`
- `packages/server/lib/nixstasis/devices/device_group.ex`
- `packages/server/lib/nixstasis/devices/device_group_membership.ex`
- `packages/server/lib/nixstasis/devices/group_authorization.ex`
- `packages/server/lib/nixstasis/devices/group_audit.ex`
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
  - `Nixstasis.Devices.list_device_groups/2`
  - `Nixstasis.Devices.list_group_memberships/2`
  - `Nixstasis.Devices.create_device_group/2`
  - `Nixstasis.Devices.update_device_group/3`
  - `Nixstasis.Devices.archive_device_group/2`
  - `Nixstasis.Devices.restore_device_group/2`
  - `Nixstasis.Devices.permanently_delete_device_group/2`
  - `Nixstasis.Devices.add_devices_to_group/3`
  - `Nixstasis.Devices.remove_devices_from_group/3`
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
  - `Nixstasis.Devices.queue_command_policy_assignment/1`
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
- `Nixstasis.Devices.DeviceGroup`
- `Nixstasis.Devices.DeviceGroupMembership`
- `Nixstasis.Devices.GroupAuthorization`
- `Nixstasis.Devices.GroupAudit`
- `Nixstasis.Devices.SchemaValidator`

### External

- Ash
- AshPhoenix
- Ecto/PostgreSQL
- Elixir Port for `ssh`
- `ncat` through SSH `ProxyCommand`

## Client-Server Interaction Details

- Device `/api/v1` runtime routes remain the Go-client compatibility boundary
  while their additive Ash-backed actions are enabled incrementally. List,
  registration, and heartbeat now have generated counterparts; command result
  acknowledgement and deferred payload retrieval remain ordered follow-on work.
  Compatibility tests continue to cover authentication, pending/approved
  registration token behavior, heartbeat directives, command results, payloads,
  and status-code semantics.
- `POST /api/v1/devices/register` calls `Devices.register_public_device/1`.
- `POST /api/v1/devices/:device_id/heartbeat` calls `Monitoring.heartbeat/2`, which updates last seen and returns pending commands. The additive generated `POST /api/json/device_runtime/devices/:device_id/heartbeat` action shares this orchestration and returns the generated `200` heartbeat contract.
- Command policy delivery reuses the pending-command queue as `apply_command_policy`; small payloads stay inline, large payloads are delivered by `payload_ref` with deferred fetch through the existing command-payload endpoint.
- `POST /api/v1/devices/:device_id/command_results` acknowledges pending commands and also records `apply_command_policy` delivery outcomes into command-policy history/status.
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

## Ash API Boundary

Device runtime migration has two deliberate HTTP surfaces:

- The Go client remains on `/api/v1` compatibility controllers until each
  generated action has runtime and transport evidence.
- The generated target is `/api/json/device_runtime/devices`: an operator-gated
  filtered list, a public registration action, and API-key-gated heartbeat,
  command-result, and payload actions. The list, registration, and heartbeat
  routes are enabled; command-result and payload routes remain ordered follow-up
  work. The API key is the `api_key` query value
  represented by the generated OpenAPI `deviceApiKey` scheme.

`Device` owns resource/action contracts. `Devices` owns registration, token
issuance, device authentication, filters, pending commands, and payload lookup;
`Monitoring` owns heartbeat orchestration and telemetry/inventory/alert side effects; scripts and command-policy contexts retain result ingestion. The
compatibility controllers only adapt legacy JSON/status/error envelopes. See the
[client-server interface](../client-server-interface.md) for the route matrix and
wire invariants.

## Device Group Contracts

- Device groups are browser control-plane data. The server exposes no public
  group HTTP API and requires no client behavior.
- `GroupAuthorization` is constructed from trusted browser identity and device
  permissions. Every mutation requires a nonblank actor ID. Production requests
  fail closed when both trusted subject and email are absent; the explicit local
  browser fallback supplies `local-development` only in local development.
- Unscoped device managers own group metadata. Scoped managers can change
  memberships only for authorized devices and only in groups visible through
  their device scope.
- `list_devices/1` accepts `group_id`, `authorized_device_ids`, and
  `load_device_groups?` options. Active-group filtering composes with existing
  search, sort, and device filters; the optional relationship preload supports
  bounded LiveView summaries rather than per-row queries.
- Metadata and membership transactions publish structured audit events only
  after commit. A separate payload-free `:device_groups_changed` event tells the
  Devices LiveView to reload scoped state.
- Structured group audit logs carry action, trusted actor ID, UTC timestamp,
  group ID, and affected device IDs. They are not stored in a dedicated database
  table, so retention belongs to the deployment logging system.

See [Device Groups](../operations/device-groups.md) for operator workflows and
conflict recovery.

## Data Model Notes

- Device records carry stable identity and operational fields such as MAC
  address, product/product name, account number, approval status, schema
  definition, last-seen/last-polled timestamps, metadata, and remote-access
  intent.
- Telemetry and schema data intentionally remain dynamic JSON structures so
  product-specific Stary scripts can evolve without one relational table per
  product payload.
- `DeviceGroup` stores normalized, case-insensitively unique metadata and an
  optional archive timestamp. Names remain reserved while archived.
- `DeviceGroupMembership` is the unique device/group join. Device deletion
  cascades membership cleanup; group deletion is restricted until the group is
  archived and empty. Archive and restore preserve memberships.
- Detailed historical product requirements live in
  [IoT Device Monitoring](../features/iot-device-monitoring/index.md) and
  [Device Detail Page](../features/device-detail-page/index.md); runtime API
  payloads live in [Client-Server Interface](../client-server-interface.md).

Traceable references:

- `packages/server/lib/nixstasis/devices.ex`
- `packages/server/lib/nixstasis/devices/device_group.ex`
- `packages/server/lib/nixstasis/devices/device_group_membership.ex`
- `packages/server/lib/nixstasis/devices/group_authorization.ex`
- `packages/server/lib/nixstasis/devices/group_audit.ex`
- `packages/server/lib/nixstasis_web/live/device_live/index.ex`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex:31-65`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex:7-27`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex:6-39`
- `packages/server/lib/nixstasis_web/live/device_live/show.ex:57-80`
