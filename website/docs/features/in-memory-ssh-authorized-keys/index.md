# In-Memory SSH Authorized Keys

Browser terminals no longer write SSH keys to `authorized_keys` files. Instead, OpenSSH asks the client, through
`AuthorizedKeysCommand`, whether a key is allowed, and the client keeps each key in memory only, for a limited time. The
server sends versioned `ssh_authorize` and `ssh_revoke` commands, logs in as the dedicated `nixstasis-support` account,
and only opens the browser's terminal socket once the device has confirmed the key.

The client and its helper talk over the fixed local socket `/run/nixstasis/ssh-authority.sock`. The native packages
and the Compose image create three separate accounts: `nixstasis` for the service, `nixstasis-support` for terminals,
and a locked `nixstasis-ssh-authority` account for the helper. The original plan is in the [design record](design.md).

## What changed for users

- A terminal logs in as `nixstasis-support`, over the same FRP and OpenSSH path as before.
- The browser gets no terminal socket token until the device answers the matching `ssh_authorize` with `OK`.
- Each authorization needs a positive time limit, a matching session reference, a properly formed public key, and the
  exact versioned content type.
- A key that is unknown, expired, revoked, malformed, for the wrong user, unavailable, or mismatched is refused; the
  helper prints nothing.
- When a terminal closes, a join fails, authorization times out, the device goes offline, SSH fails to start, or the
  lease expires, the server deletes its key material first, then queues a revoke if it can. Revokes are limited and
  safe to repeat.
- Restarting the client empties its memory, which ends every browser terminal authorization.

## How it fits in

Phoenix decides which operators may open a terminal, tracks each session, and holds the private keys. The client
checks keys on the device, expires them, revokes them, and answers the helper. OpenSSH enforces the login for
`nixstasis-support`; the helper only passes questions along, and FRP only carries the connection. There is no
capability negotiation, no TCP socket, no fallback to key files, and no extra privilege for the helper.

## Running it

The installers and the Compose client set up the support account, the locked helper account, the socket group, the
runtime directory, the root-owned helper, and the OpenSSH configuration. The helper and the client must both be running
for support logins to work; if either is missing, the login is refused rather than falling back to a file.

The socket path is fixed at `/run/nixstasis/ssh-authority.sock`. Any other socket setting is ignored, with a warning.

In the Compose simulator, systemd runs inside the container and the unprivileged poll service cannot use `systemd-run`.
There, the poll service runs the FRP session itself, for up to an hour. Native installs managed by root keep using the
transient systemd unit.

The real-sshd integration test runs on Linux hosts. A separate Compose and browser smoke test, in a configured lab,
covers support logins, a harmless diagnostic, closing the terminal, FRP cleanup, and the helper refusing a revoked key.

## Differences from the design

- **One fixed socket.** The socket path is fixed rather than configurable, so the poller and the helper can never
  disagree about it, and a request can never choose its own path.
- **Two kinds of test evidence.** The real-sshd integration test and the Compose and browser smoke test are recorded
  separately; passing one does not count as passing the other.
- **FRP in the simulator.** As described above, the Compose simulator runs the FRP session from the poll service when it
  cannot create a systemd unit. Native installs still use systemd.
- **Revoke migration.** The terminal-revoke migration removes old duplicate revoke rows before adding its uniqueness
  constraint, and leaves unrelated command rows alone.
- **Where the contract lives.** The command format is maintained in the reference and OpenAPI pages; the design remains
  the record of the plan.

## Not included

- Browser terminal keys are never written to `authorized_keys`.
- There is no file fallback, capability negotiation, TCP socket, password login, or privileged or general-purpose helper.
- FRP, and the way Phoenix and Caddy authorize operators, did not change.

## Tests

- `packages/client/internal/sshauth/store_test.go`, `keys_test.go`, and `ipc_test.go`: the in-memory store, key checks,
  and the socket.
- `packages/client/internal/sshauth/sshd_integration_test.go`: `AuthorizedKeysCommand` with a real sshd (Linux only).
- `packages/client/cmd/nixstasis/ssh_authorized_keys_test.go`: the helper.
- `packages/client/internal/commands/handler_test.go`: handling `ssh_authorize` and `ssh_revoke`.
- `packages/client/cmd/nixstasis/poll_test.go`: the fixed socket path.
- `packages/client/build/tests/native_packaging_test.sh`: the installer's accounts, socket group, runtime directory,
  helper permissions, and sshd configuration.
- `packages/server/test/nixstasis/devices/ssh_client_test.exs` and `ssh_key_manager_test.exs`: the server's key
  material and SSH client.
- `packages/server/test/nixstasis/devices_test.exs`: queueing commands and the terminal authorization status.
- `packages/server/test/nixstasis_web/controllers/heartbeat_controller_test.exs`: the `ssh_authorize` payload in
  heartbeats.
- `packages/server/test/nixstasis_web/channels/terminal_channel_test.exs` and
  `packages/server/test/nixstasis_web/live/device_live_test.exs`: waiting for the device's confirmation, and cleanup.
- `packages/server/test/nixstasis/repo/migrations/deduplicate_terminal_revokes_test.exs`: the revoke migration.
- `deploy/compose/scripts/ssh_terminal_smoke.sh`: the Compose and browser smoke test.

## Related pages

- [API & Runtime Contracts](../../reference/contracts.md#browser-terminal-ssh-authorization-contract)
- [Runtime Boundaries](../../runtime-boundaries.md#browser-terminal-authorization)
- [Data Flow](../../data-flow.md#browser-terminal-session)
- [Client-Server Interface](../../client-server-interface.md)
- [Server Devices](../../modules/server-devices.md)
- [Client Command Handler](../../modules/client-command-handler.md)
- [Client FRP Manager](../../modules/client-frp-manager.md)
- [Client Transport](../../modules/client-transport.md)
- [Deployment](../../operations/deployment.md)
- [Device API OpenAPI](../../reference/openapi/device-api.yaml)
- Client installation and packaging: `packages/client/README.md`
- Compose deployment details: `deploy/compose/README.md`
