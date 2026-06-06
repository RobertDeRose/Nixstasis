# In-Memory SSH Authorized Keys

## Summary

Replace file-based browser-terminal SSH authorization with an OpenSSH
`AuthorizedKeysCommand` integration backed by the Nixstasis client runtime. The
Phoenix server still issues short-lived terminal keys after operator
authorization. Managed devices store those public keys in memory only, and sshd
asks a small local helper whether an offered key blob is currently authorized for
the support account.

This feature removes new-install dependence on writing browser-terminal keys to
`authorized_keys`, keeps operator repair login separate from the `nixstasis`
service account, and allows the client daemon to move toward an unprivileged
runtime without broad filesystem write authority over operator SSH state.

## Goals

- Authenticate browser terminal SSH sessions through OpenSSH
  `AuthorizedKeysCommand` instead of persistent browser-terminal key files.
- Keep ephemeral terminal public keys in client memory only.
- Migrate browser terminal SSH login from the current `nixstasis` account to the
  dedicated `nixstasis-support` repair account.
- Run the OpenSSH helper as a separate locked-down
  `nixstasis-ssh-authority` identity, not as `nixstasis-support` and not as a
  privileged command runner.
- Expose a local-only Unix-domain IPC endpoint under `/run/nixstasis/` for key
  authorization checks.
- Make browser terminal startup a clean dynamic-auth cutover: clients that do
  not advertise the dynamic capability receive an explicit upgrade-required
  failure instead of a best-effort legacy terminal session.
- Keep browser/operator authorization in Phoenix and Caddy separate from
  device-side SSH key authorization.

## Non-Goals

- Replacing FRP or changing the FRPS TCP mux route.
- Replacing OpenSSH with a custom remote shell daemon.
- Supporting password-based support login.
- Installing permanent operator SSH keys or long-lived per-operator device-local
  accounts.
- Building a general privileged command execution framework.
- Granting broad sudo or run0 privileges to the `nixstasis` service account or
  the dynamic-key helper.
- Deleting legacy operator-owned `authorized_keys` files during package upgrade.

## Current Behavior

- The server creates ephemeral SSH keys for terminal sessions and stores private
  key material behind an expiring session ref in
  `Nixstasis.Devices.SshKeyManager`.
- The device detail LiveView currently queues `ssh_authorize` before creating the
  terminal session ref.
- The heartbeat renderer currently serializes command id, type, args, payload,
  payload ref, and queued time; it does not serialize top-level `public_key` for
  queued command maps unless that boundary is updated.
- The Go client handles `ssh_authorize` by resolving an allowed
  `authorized_keys` path and appending the provided public key to that file.
- The packaged default currently includes `runtime.authorized_keys_path` under
  `/var/lib/nixstasis/.ssh/authorized_keys`.
- The server-side SSH client currently connects as
  `nixstasis@atom-<device>-ssh` through the FRP TCP mux route.
- The file-based path requires the client daemon to write into account SSH state,
  which is the wrong privilege boundary for an unprivileged client.

## Proposed Runtime Contract

### Capability advertisement

Dynamic SSH authorization is selected by an explicit device capability in the
heartbeat request. The Go client sends the capability on every heartbeat:

```json
{
  "telemetry": {},
  "connection_status": {},
  "capabilities": ["ssh_authorize_dynamic_v1"]
}
```

Semantics:

- `ssh_authorize_dynamic_v1` means the client supports in-memory
  `ssh_authorize` commands, the local helper IPC server, and the
  `nixstasis-support` target user.
- The server treats an absent or unknown `capabilities` list as not eligible for
  browser terminal startup. It must not silently send a file-compatible terminal
  authorization and then connect as the wrong Unix account.
- Capability evaluation for terminal startup uses the latest authenticated
  heartbeat capability observed for that device. A device with no known dynamic
  capability fails terminal startup with an operator-visible upgrade-required
  error before exposing a browser terminal token.
- The latest observed capability is a compatibility gate, not an authorization
  grant. Browser/operator authorization still comes from Phoenix/Caddy, and the
  terminal command is still delivered only over authenticated device heartbeat.
- The stored observation must be refreshed by authenticated heartbeats and should
  expire with heartbeat freshness so a long-offline device does not look
  indefinitely dynamic-capable.

### `ssh_authorize` command payload

Dynamic-capable clients receive a command payload with explicit SSH auth metadata
and no required `authorized_keys_path`:

```json
{
  "command_id": "<command-id>",
  "type": "ssh_authorize",
  "public_key": "ssh-ed25519 AAAA... nixstasis-remote-access",
  "payload": {
    "content_type": "application/vnd.nixstasis.ssh-authorize+json;version=1",
    "name": "<session-ref>",
    "data": "{\"target_user\":\"nixstasis-support\",\"ttl_seconds\":300,\"session_ref\":\"<session-ref>\"}"
  }
}
```

Semantics:

- `public_key` is the full authorized-keys-style public key generated by the
  server.
- `target_user` is required and initially must be `nixstasis-support`.
- `ttl_seconds` must be positive and bounded by the server terminal-session TTL.
- `session_ref` is stored with the authorization so explicit revocation can
  remove the key later.
- The heartbeat JSON boundary must serialize the exact response shape consumed by
  the Go client. If the public key remains top-level, `HeartbeatJSON.command_data/1`
  must emit `public_key` for `ssh_authorize`; otherwise the Go command contract
  must move the public key into `payload.data` consistently across server docs,
  OpenAPI, and client structs.
- Legacy file-compatible `ssh_authorize` parsing may remain in the Go client as
  an explicitly configured compatibility path for old server payloads and tests,
  but the reviewed Phoenix browser-terminal flow requires dynamic auth and the
  `nixstasis-support` target user.

### Terminal session sequencing

The browser terminal flow must avoid racing SSH login before the device has
stored the dynamic authorization.

Required order for dynamic-capable clients:

1. Operator requests a browser terminal session.
2. Server generates the SSH key pair.
3. Server creates the terminal session ref before queueing the command.
4. Server queues `ssh_authorize` with the public key, session ref, target user,
   and TTL.
5. If command queueing fails, the server clears the terminal session ref and does
   not expose a browser terminal token.
6. Client claims the command on heartbeat, validates the payload, stores the key
   in memory, and returns an OK command result.
7. Only after the OK command result is observed should the UI expose or activate
   the terminal socket token for the browser.
8. If authorization acknowledgement times out or fails, the server clears the
   terminal session ref and reports a terminal-start failure to the UI.
9. The terminal channel consumes the session ref when starting the server-side
   SSH process.

This is a deliberate change from the current eager token exposure. It prevents a
failed early SSH attempt from consuming the server-side terminal session before
sshd can authorize the key.

### Client-side authorization state

The client maintains an in-memory SSH authorization store keyed by canonical key
material/fingerprint and target Unix user. Each entry records:

- canonical public key bytes or stable fingerprint;
- target Unix user;
- command id;
- terminal session ref;
- issued-at timestamp;
- expiry timestamp;
- optional device/session context safe for diagnostics.

The store must:

- reject malformed public keys before storing them;
- deny wrong-user, expired, revoked, unknown, or malformed lookup requests;
- remove entries after expiry;
- support explicit revocation by command id/session ref when available;
- start empty after client restart, making restart invalidate terminal keys.

### Local IPC

The client listens on a Unix-domain socket under `/run/nixstasis/`, for example
`/run/nixstasis/ssh-authority.sock`. The socket is local-only and must not have a
TCP equivalent.

The IPC protocol uses OpenSSH key material rather than trusting an
already-formatted public-key line from sshd.

Request:

```json
{"user":"nixstasis-support","key_type":"ssh-ed25519","key_blob":"AAAA..."}
```

Allow response:

```json
{"authorized":true,"key_type":"ssh-ed25519","key_blob":"AAAA..."}
```

Deny response:

```json
{"authorized":false}
```

The helper prints an authorized key only for an explicit allow response whose
canonical key material matches the offered key. Any parse error, timeout, missing
socket, invalid response, wrong user, unknown key, or expired key results in no
stdout output.

IPC requirements:

- socket path is fixed or configured from trusted local config only;
- helper request size is bounded;
- client response size is bounded;
- helper deadline is short enough not to stall OpenSSH authentication;
- stale sockets are removed only when they are Unix sockets at the expected path;
- permissions allow the client runtime and `nixstasis-ssh-authority` to
  communicate while denying untrusted local users.

## OpenSSH And Accounts Design

New installs configure sshd for support browser terminals with a drop-in
equivalent to:

```sshconfig
Match User nixstasis-support
    PubkeyAuthentication yes
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AuthorizedKeysFile none
    AuthorizedKeysCommand /usr/libexec/nixstasis/ssh-authorized-keys %u %t %k
    AuthorizedKeysCommandUser nixstasis-ssh-authority
```

For older OpenSSH distributions that use `ChallengeResponseAuthentication`
instead of `KbdInteractiveAuthentication`, packaging may include the compatible
spelling as long as password and keyboard-interactive login are disabled for
`nixstasis-support`.

Account and privilege rules:

- `nixstasis-support` is the operator login account for repair workflows.
- `nixstasis-ssh-authority` is a locked system account used only by
  `AuthorizedKeysCommand`.
- The helper must not be writable by either account.
- The helper must not execute arbitrary client commands or write files based on
  sshd input.
- `nixstasis-support` may keep the documented repair privileges, including sudo
  and/or run0, but those privileges must not be granted to
  `nixstasis-ssh-authority`.

## Helper Command Design

Install `/usr/libexec/nixstasis/ssh-authorized-keys` as a small Go command or
subcommand shipped with the client package. It accepts exactly the OpenSSH
arguments from the configured drop-in:

```text
ssh-authorized-keys <unix-user> <key-type> <base64-key-blob>
```

Behavior:

- validate argument count, key type, and key blob size before dialing IPC;
- canonicalize the offered OpenSSH key material before lookup;
- send the username, key type, and key blob to the local socket;
- print `<key-type> <base64-key-blob>` followed by a newline only when the client
  explicitly authorizes it;
- print nothing for denial or any failure;
- return quickly on timeout;
- log only diagnostics that do not leak private key material. Public-key
  fingerprints are acceptable; full public keys should be avoided in routine
  logs.

## Server Design

- Continue generating terminal SSH key pairs server-side.
- Continue storing private key material behind an opaque terminal session ref.
- Change the server-side SSH client destination user from `nixstasis` to
  `nixstasis-support` so it matches the sshd `Match User` block and dynamic
  payload `target_user`.
- Queue terminal authorization commands with public key, target user, TTL, and
  session metadata.
- Require a latest observed `ssh_authorize_dynamic_v1` heartbeat capability
  before queueing browser-terminal authorization. If the capability is absent,
  fail terminal startup with an upgrade-required UI error and do not expose a
  terminal socket token.
- Gate browser terminal token activation on successful `ssh_authorize` command
  acknowledgement for dynamic clients.
- Clear server-side terminal session refs on queue failure, command failure,
  authorization timeout, terminal join failure, terminal close, and terminal
  session expiry.
- Keep terminal close/session cleanup independent from device-side expiry; if an
  explicit revoke command exists or is added, use it as a best-effort early
  cleanup signal. The implementation adds an `ssh_revoke` command
  (`application/vnd.nixstasis.ssh-revoke+json;version=1`) sent to clients that
  advertise `ssh_authorize_dynamic_v1`. Revoke queueing is fire-and-forget: the
  command is gated on the dynamic capability, queued from
  `DeviceLive.Show.clear_*` and `TerminalChannel` join-failure / terminate
  paths, and never blocks terminal cleanup. Clients in turn call
  `sshauth.Store.RevokeSession(session_ref)`; if the session ref is unknown
  the operation is a no-op.

## Client Design

- Add an internal package for SSH authorization state and IPC server behavior.
- Add heartbeat capability advertisement for `ssh_authorize_dynamic_v1`.
- Update the command handler so dynamic `ssh_authorize` payloads add an in-memory
  authorization instead of appending a file.
- Keep the existing file-based handler path only as an explicitly configured
  client-side compatibility branch for old server payloads and tests. It is not
  the server browser-terminal rollout path after the support-account cutover.
- Start the Unix socket server as part of the poll/client runtime lifecycle.
- Ensure client restart starts with an empty authorization store.
- Ensure command-result output reports safe metadata such as target user,
  session ref, expiry, and whether dynamic auth was used; it must not report
  private key material.
- Remove new-install defaults and examples that imply browser terminal SSH keys
  should be persisted through `runtime.authorized_keys_path`. Legacy fallback may
  remain configurable and documented as compatibility-only.

## Packaging And Deployment Design

Client packaging must:

- create or update `nixstasis-support` for operator SSH sessions;
- create or update locked `nixstasis-ssh-authority` for OpenSSH helper execution;
- install `/usr/libexec/nixstasis/ssh-authorized-keys` root-owned and not
  writable by service/support/helper users;
- install an sshd config drop-in for the support account;
- safely reload or restart sshd when systemd is available;
- preserve existing `authorized_keys` files on upgrade unless a later design
  explicitly defines cleanup;
- ensure new installs do not depend on any browser-terminal `authorized_keys`
  path, including `/var/lib/nixstasis/.ssh/authorized_keys` or
  `/var/lib/nixstasis-support/.ssh/authorized_keys`;
- ensure `/run/nixstasis/` ownership and mode are compatible with the client
  service user and helper identity only.

Socket permission model:

- create a local system group that both the client runtime and
  `nixstasis-ssh-authority` can use for socket access;
- create `/run/nixstasis` with mode `0750` and group ownership limited to that
  socket-access group;
- create `ssh-authority.sock` with mode `0660`, owned by the client runtime
  identity and the socket-access group;
- verify `nixstasis-ssh-authority` can connect and an unrelated local user cannot;
- prefer systemd `RuntimeDirectory=nixstasis` cleanup when the client service is
  managed by systemd.

Compose/dev-lab support should exercise the installed helper path and sshd
configuration rather than bypassing OpenSSH with direct shell access.

## Security And Failure Behavior

- Unknown, expired, revoked, malformed, or wrong-user keys are denied by printing
  no authorized keys.
- If the client process or socket is unavailable, support SSH key auth is denied.
- The IPC socket is local-only and permissioned for the helper/client boundary.
- The helper trusts only its argv and configured socket path; it never follows
  user-controlled filesystem paths.
- Public-key canonicalization happens before storage and comparison.
- Logs must not expose private keys. Routine logs should prefer command ids,
  session refs, target users, and public-key fingerprints.
- Restarting the client invalidates all in-memory terminal authorizations.
- Support SSH login remains public-key-only for `nixstasis-support`; password and
  keyboard-interactive paths must not bypass the dynamic key helper.

## Migration And Compatibility

- New installs prefer `AuthorizedKeysCommand` and do not require a persistent
  browser-terminal `authorized_keys` file.
- Existing file-based `runtime.authorized_keys_path` remains a temporary
  client-side fallback for explicitly configured legacy command payloads, but it
  does not preserve browser-terminal compatibility for clients that lack
  `ssh_authorize_dynamic_v1` after the server starts connecting as
  `nixstasis-support`.
- Server browser-terminal startup requires a latest observed dynamic capability;
  absent or unknown capability produces an upgrade-required result instead of a
  legacy terminal session.
- The fallback must be explicitly described as compatibility-only, not the normal
  remote terminal authorization path.
- Package upgrades preserve legacy `authorized_keys` files to avoid deleting
  operator-owned keys unexpectedly.

## Docs And Pages Likely Affected

- `docs/src/client-server-interface.md`
- `docs/src/data-flow.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/modules/client-command-handler.md`
- `docs/src/modules/client-transport.md`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/edge-frp.md`
- `docs/src/modules/server-devices.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/reference/openapi/device-api.yaml`
- `docs/src/features/index.md`
- `docs/src/SUMMARY.md`
- `packages/client/README.md`
- `packages/server/README.md`
- `docs/src/planned-features.md`

## Validation Plan

- Unit tests for the client in-memory authorization store: add, match, expiry,
  revoke, restart-empty initialization, malformed-key rejection, and wrong-user
  denial.
- Unit tests for the helper with a fake Unix socket: allow, deny, timeout,
  malformed argv input, invalid response, missing socket, wrong OpenSSH token
  shape, and oversized payload handling.
- Unit tests for the IPC server request/response behavior, stale socket cleanup,
  and socket permission checks where practical.
- Client transport tests proving heartbeat requests advertise
  `ssh_authorize_dynamic_v1`.
- Client command-handler tests proving dynamic `ssh_authorize` stores keys in
  memory and legacy payloads still use the file fallback only when configured.
- Server tests proving heartbeat command serialization includes the exact dynamic
  `ssh_authorize` JSON shape, TTL/session fields, target user, capability-based
  dynamic/legacy behavior, and top-level public-key handling.
- Server tests proving terminal startup creates session refs before queueing,
  cleans up on queue/ack failure, gates terminal token activation on OK command
  result, and uses `nixstasis-support` as the SSH destination user.
- Packaging tests or scripted checks for installed helper path, sshd drop-in,
  support user, authority user, socket group/modes, sudo/run0 separation,
  public-key-only support login, and absence of new-install browser-terminal file
  writes.
- Container integration test with real sshd where `AuthorizedKeysCommand` invokes
  the helper with `%u %t %k`, authenticates a short-lived key, and denies it
  after TTL expiry. The current implementation is a Go integration test in
  `packages/client/internal/sshauth/sshd_integration_test.go` that forks the
  host's `/usr/sbin/sshd` on a high loopback port, points
  `AuthorizedKeysCommand` at a wrapper which execs a freshly built
  `nixstasis ssh-authorized-keys`, and exercises allow / unknown / expired /
  wrong-user / revoked-session flows through the system `ssh` client. The
  test is Linux-only (CI) and skips on macOS developer workstations because
  the platform OpenSSH build's `safe_path` check rejects otherwise valid
  helper paths. The wrapper script
  `deploy/compose/scripts/ssh_terminal_smoke.sh` invokes the test and is the
  entry point for the dev-lab smoke step below.
- Compose dev-lab smoke test that launches a browser terminal, runs `whoami` and
  verifies `nixstasis-support`, runs a safe diagnostic command such as
  `sudo systemctl status nixstasis-poll.service` or
  `run0 systemctl status nixstasis-poll.service`, closes the session, and
  verifies a later expired key is denied. In this implementation the
  end-to-end SSH flow is validated by the Go real-sshd integration test
  above (which already covers allow, deny, expiry, and revoked-session
  flows through the system `ssh` client). The
  `deploy/compose/scripts/ssh_terminal_smoke.sh` wrapper is the dev-lab
  entry point and is suitable for inclusion in the Compose smoke pipeline.
- Documentation validation for changed mdBook pages and OpenAPI schema checks for
  the device command contract.

## Reconciliation Bookends

- Before implementation, read package-level agent instructions for client/server
  changes and confirm the active worktree is
  `feat/in-memory-ssh-authorized-keys`.
- Before implementation, reconcile that this feature spec was seeded from a
  planned feature entry that may not exist on the selected base branch; add or
  update the `docs/src/planned-features.md` entry before marking implementation
  complete.
- During implementation, keep server command payloads, heartbeat capability
  advertisement, client command handling, packaging, OpenAPI, and docs aligned in
  the same unit of work.
- Before completion, search code and docs for stale file-based
  browser-terminal-key guidance and reconcile it with the dynamic auth rollout
  story.
- Before completion, verify new-install defaults no longer configure any
  browser-terminal persistent `authorized_keys` path as the normal path.
