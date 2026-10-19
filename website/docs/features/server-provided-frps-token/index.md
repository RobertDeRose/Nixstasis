# Server-Provided FRPS Token

Devices no longer share one FRPS secret. Instead, while a device has an authorized remote-access lease, each heartbeat
response carries a signed credential tied to that device and lease. The client starts `frpc` when a credential
arrives and stops it when none does, and passes the secret to `frpc` through an environment file only root can read.
The original plan is in the [design record](design.md).

## What changed for users

Remote access starts when the server sends a credential, and stops when it stops sending one. There is no longer a
fleet-wide FRPS secret to put in client configuration.

## How it fits in

Phoenix signs a short-lived credential for each device. FRPS checks it with Phoenix, through its internal plugin, on
every `Login` and `NewProxy`. Starting and stopping `frpc` stays inside the client's FRP manager, using its own route
templates.

## Running it

The fleet-wide FRPS client secret is gone. Device credentials last only as long as the session, and are signed with
`SECRET_KEY_BASE`. FRPS refuses any credential, or proxy, that does not match the device. How to respond if credentials
leak is in [Secret Rotation](../../operations/secret-rotation.md#frps-device-credentials).

## Differences from the design

- **Tighter identity.** FRP route names are built from the device UUID the server assigned, credentials are signed per
  device, and Phoenix authorizes every FRPS `Login` and `NewProxy`.
- **Leases.** Each lease records its own identity, owner, fixed profile, expiry, and revocation. The remote-access
  fields on a device only mirror the current lease; they never grant access themselves. A provisioning delivery uses
  its own UUID to pick up the same lease after a restart, and can never renew or close another operator's access.
- **Which lease wins.** A provisioning lease wins over browser and direct leases; otherwise the newest wins. The winning
  lease sets both the profile and how long access lasts. FRPS checks that exact lease, so another open lease cannot
  make a revoked credential valid again.
- **What the client sees.** Heartbeats include `remote_access_lease_id` and `remote_access_expires_at_ms`, so the client
  can tell a new lease from a re-signed credential, and restarts `frpc` only for a new lease. Older credentials that
  were not tied to a lease no longer work. Other device updates cannot overwrite the lease fields, and profile
  preferences are applied in the same locked update.

The full lease rules are in [Server Devices](../../modules/server-devices.md).

## Not included

- Revoking access does not cut an established tunnel at once. FRPS refuses new logins and proxies straight away, and the
  tunnel itself stops after the device's next authenticated heartbeat.
- Browser and terminal authorization stay separate from FRPS authorization.

## Tests

- `packages/client/cmd/nixstasis/poll_test.go` and `packages/client/internal/transport/client_runtime_test.go`:
  starting and stopping `frpc` with and without a credential, and a new lease versus a re-signed credential.
- `packages/server/test/nixstasis_web/controllers/heartbeat_controller_test.exs`: signed, lease-bound credentials in
  heartbeats.
- `packages/server/test/nixstasis_web/controllers/frp_authorization_controller_test.exs` and
  `frp_access_controller_test.exs`: authorizing FRPS `Login` and `NewProxy`, and refusing proxies for another device.
- `packages/server/test/nixstasis/devices/remote_access_leases_test.exs`: lease identity, ownership, precedence,
  revocation, and keeping the device fields in step.
- `deploy/compose/scripts/check_frps_config.sh`: renders the Compose `frps.toml`, plugin entry included, and checks it
  with the pinned `frps` binary.
- `mix ash.codegen --check`: the lease resource and its migrations.

## Related pages

- [Client-Server Interface](../../client-server-interface.md)
- [Client FRP Manager](../../modules/client-frp-manager.md)
- [Gateway FRP](../../modules/gateway-frp.md)
- [Server Devices](../../modules/server-devices.md)
- [Secret Rotation](../../operations/secret-rotation.md)
- [Deployment](../../operations/deployment.md)
