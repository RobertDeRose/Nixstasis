# In-Memory SSH Authorized Keys Tasks

> **Scope note:** the in-memory `ssh_authorize` path is the only path the server
> emits. There is no heartbeat capability advertisement, no capability gate, and
> no file-based fallback. Tasks that described those older shapes are kept here
> marked **cancelled** for traceability; no code or tests should still reference
> them.

## Setup

- [x] T000 Confirm the active worktree is
  `feat/in-memory-ssh-authorized-keys` and the feature spec matches the intended
  `in-memory-ssh-authorized-keys` brief.
- [x] T001 Read `packages/AGENTS.md`, `packages/client/AGENTS.md`, and
  `packages/server/AGENTS.md` before changing package files.
- [x] T002 Inventory current browser-terminal SSH flow across server terminal
  session creation, `ssh_authorize` command delivery, heartbeat serialization,
  client command handling, packaging, and docs.
- [x] T003 Reconcile `docs/src/planned-features.md` on this branch with the
  reviewed feature spec if the planned feature entry is absent or stale.

## Contract Foundation

- [x] T004 **cancelled.** The dynamic `ssh_authorize` path is the only path the
  server emits; there is no heartbeat capability advertisement. The
  `capabilities` field is gone from the heartbeat, and the Go client does not
  send one. See `design.md` "Proposed Runtime Contract" for the final shape.
- [x] T005 **cancelled.** No transport or transport test advertises a capability
  field. The heartbeat body only carries `telemetry` and `connection_status`.
- [x] T006 **cancelled.** No latest-observed capability gate exists on the
  server. Every authenticated device is dynamic-capable for terminal
  authorization.
- [x] T007 Render the exact dynamic `ssh_authorize` JSON shape (public key at
  top level, `payload.content_type =
  application/vnd.nixstasis.ssh-authorize+json;version=1`,
  `target_user=nixstasis-support`, `ttl_seconds`, `session_ref`) consumed by the
  Go client. Confirmed in
  `HeartbeatJSON.command_data/1` and the updated `device_live_test.exs`.
- [x] T008 **cancelled.** No capability-based tests exist; the
  `capability-based dynamic/legacy behavior` and `upgrade-required failures`
  scenarios are gone. Server tests cover the dynamic `ssh_authorize` shape
  directly.

## Client Authorization Store And IPC

- [x] T009 Add a client internal SSH authorization package for in-memory key
  entries keyed by canonical key material/fingerprint and target Unix user.
  Implementation: `packages/client/internal/sshauth/keys.go` and
  `packages/client/internal/sshauth/ipc.go`.
- [x] T010 Implement authorization store add, match, expiry, revoke by command id
  or session ref, and restart-empty initialization behavior.
- [x] T011 Reject malformed public keys before storage and normalize valid keys
  before comparison.
- [x] T012 Add unit tests for store allow, unknown key denial, wrong-user denial,
  malformed-key rejection, expiry, explicit revoke, and empty store after restart.
- [x] T013 Implement a local Unix-domain IPC server under `/run/nixstasis/` for
  SSH authorization lookups.
- [x] T014 Bound IPC request and response sizes and enforce short lookup
  deadlines.
- [x] T015 Implement stale-socket cleanup only for Unix sockets at the expected
  path.
- [x] T016 Ensure IPC socket permissions allow only the client runtime identity
  and `nixstasis-ssh-authority` helper identity to communicate.
- [x] T017 Add IPC server tests for allow, deny, malformed request, oversized
  request, invalid method/payload, timeout/cancellation, missing/removed socket,
  and stale-socket handling where practical.

## Helper Command

- [x] T018 Add `/usr/libexec/nixstasis/ssh-authorized-keys` as a small Go helper
  command or installed client subcommand. Implementation:
  `packages/client/cmd/nixstasis/ssh_authorized_keys.go` and the
  `build/root-dir/usr/libexec/nixstasis/ssh-authorized-keys` shell wrapper.
- [x] T019 Make the helper accept exactly `<unix-user> <key-type>
  <base64-key-blob>` from OpenSSH `%u %t %k` and reject invalid argument counts,
  key types, or oversized key input without contacting IPC.
- [x] T020 Make the helper query the local Unix socket with `user`, `key_type`,
  and `key_blob`, then print `<key-type> <base64-key-blob>` only for an explicit
  allow response.
- [x] T021 Make helper denial paths print no stdout for unknown, expired,
  malformed, wrong-user, timeout, invalid-response, and client-unavailable cases.
- [x] T022 Add helper tests with a fake Unix socket server covering allow, deny,
  timeout, invalid response, missing socket, malformed OpenSSH argv, wrong user,
  and oversized input.

## Client Command Handling And Runtime

- [x] T023 Extend `ssh_authorize` command parsing to accept dynamic auth payloads
  with target user, TTL, session ref, and public key. Implementation:
  `packages/client/internal/commands/handler.go` calls into the in-memory store
  via the IPC server.
- [x] T024 Store dynamic `ssh_authorize` keys in memory instead of appending to
  `authorized_keys`.
- [x] T025 **cancelled.** No file-based `authorized_keys_path` handling remains.
  The client has no `runtime.authorized_keys_path` field, and the command
  handler does not branch on a legacy payload shape. This task is fully
  superseded by removing the legacy path entirely.
- [x] T026 Remove new-install defaults and example configuration that make
  `runtime.authorized_keys_path` appear to be the normal browser-terminal path.
  The field is gone from the runtime YAML and from
  `build/container-entrypoint.sh`.
- [x] T027 Return safe command-result metadata for dynamic authorization without
  leaking key material.
- [x] T028 Start and stop the SSH authorization IPC server with the client poll
  runtime lifecycle.
- [x] T029 Add client command-handler tests for dynamic auth success, malformed
  payloads, invalid TTL, and wrong target user. (Legacy file fallback coverage
  is **cancelled**; no file path exists in the handler.)
- [x] T030 Add poll/runtime tests proving the IPC server is available while the
  client is running and unavailable after shutdown.

## Server Terminal Contract

- [x] T031 Change terminal session startup to create the server terminal session
  ref before queueing `ssh_authorize` so the queued command can carry the ref.
- [x] T032 Queue dynamic terminal authorization commands with public key, target
  user `nixstasis-support`, TTL, and session metadata.
- [x] T033 **cancelled.** No capability-based filtering of `ssh_authorize`
  commands. `pop_pending_commands/1` is single-arg and emits every queued
  command; there is no `dynamic_filter` shape left to honor.
- [x] T034 **cancelled.** No upgrade-required terminal-start failure path. There
  is no capability gate that could fail it, so the upgrade-required UI error is
  gone too.
- [x] T035 Change the server SSH client destination user from `nixstasis` to
  `nixstasis-support`.
- [x] T036 Gate browser terminal token activation on an OK `ssh_authorize` command
  result.
- [x] T037 Clear server-side terminal session refs on queue failure, authorization
  failure, acknowledgement timeout, join failure, terminal close, and expiry.
- [x] T038 Server tests cover dynamic `ssh_authorize` payload shape, TTL bounds,
  target user, session ref, heartbeat public-key serialization, and omission
  of `authorized_keys_path`. (Capability / upgrade-required scenarios are
  **cancelled**.)
- [x] T039 Server tests cover terminal sequencing, queue-failure cleanup,
  command-result gating, timeout cleanup, and SSH destination user.
- [x] T040 Add or update terminal close/revoke behavior if an existing command or
  server hook can explicitly revoke client-side in-memory authorization.
  Implementation: server queues a new `ssh_revoke` command
  (`application/vnd.nixstasis.ssh-revoke+json;version=1`, payload
  `{"session_ref":...}`); there is no capability filter on it. Queueing
  happens in `Devices.queue_terminal_revoke/2`, called from
  `DeviceLive.Show.clear_*` and `TerminalChannel` join-failure / terminate
  paths as a best-effort fire-and-forget signal. The Go client adds an
  `ssh_revoke` case to `commands.ExecuteBatch` that calls
  `sshauth.Store.RevokeSession`; the unknown-session case is a no-op. See
  `design.md` "Server Design" and "Client Design" for the full contract.

## Packaging And Runtime Contract

- [x] T041 Install the helper at
  `/usr/libexec/nixstasis/ssh-authorized-keys` with root-owned, non-writable
  permissions. Wrapper script shipped in
  `packages/client/build/root-dir/usr/libexec/nixstasis/ssh-authorized-keys`;
  client binary itself is installed by the existing package scripts and is
  not writable by the helper or support users.
- [x] T042 Add an sshd config drop-in for `nixstasis-support` using
  `PubkeyAuthentication yes`, `AuthenticationMethods publickey`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
  `AuthorizedKeysFile none`, `AuthorizedKeysCommand`, and
  `AuthorizedKeysCommandUser nixstasis-ssh-authority`. Implementation:
  `packages/client/build/root-dir/etc/ssh/sshd_config.d/nixstasis-support.conf`.
- [x] T043 Create or update the `nixstasis-support` operator account in package
  install scripts without deleting existing operator-owned SSH state.
- [x] T044 Create or update locked `nixstasis-ssh-authority` as the OpenSSH helper
  identity and ensure it does not receive sudo/run0 repair privileges.
- [x] T045 Create a socket-access group and ensure the client runtime identity and
  `nixstasis-ssh-authority` can use it for IPC.
- [x] T046 Ensure `/run/nixstasis/` is mode `0750` and the socket is mode `0660`
  with ownership that permits only the client runtime and helper identity.
- [x] T047 Prefer systemd `RuntimeDirectory=nixstasis` cleanup for managed client
  service runs and test stale socket cleanup for non-systemd/fallback runs.
- [x] T048 Safely reload or restart sshd from package install scripts when systemd
  is available.
- [x] T049 Extend release/package verification to assert helper path, sshd drop-in,
  support user, authority user, socket group/modes, sudo/run0 separation, and
  public-key-only support login. (Legacy file preservation and the "no
  new-install browser-terminal `authorized_keys` dependency" check are
  **cancelled**: no `authorized_keys_path` is configured or referenced.)
- [x] T050 Add container packaging or integration coverage for the sshd drop-in on
  supported Linux targets where practical.

## Documentation

- [x] T051 Skipped: `docs/src/client-server-interface.md` no longer contains
  stale SSH-authorize payload or capabilities-gate guidance; the terminal flow
  details are covered by the `data-flow.md` update (T052).
- [x] T052 Update `docs/src/data-flow.md` for the browser-terminal flow:
  session-ref creation before queueing, command-result gating, OpenSSH helper,
  Unix IPC, and in-memory authorization.
- [x] T053 Skipped: `docs/src/runtime-boundaries.md` SSH references are at a
  higher architectural level and already correct (SshClient, FRP, Compose SSH
  details). No capability-gate or file-based language remains.
- [x] T054 Skipped: `docs/src/modules/client-command-handler.md` is a minimal
  list of command types and does not describe payloads or fallback behavior.
- [x] T055 Skipped: `docs/src/modules/client-transport.md` heartbeat request/response
  section already omits capabilities and uses the current struct shape.
- [x] T056 Skipped: `docs/src/modules/client-frp-manager.md` IPC lifecycle changes
  are internal to the client poll runtime; the FRP manager doc only describes
  `remote_access_token` behavior which is unchanged.
- [x] T057 Skipped: `docs/src/modules/edge-frp.md` SSH references are about the
  TCP mux route (unchanged), not key authorization.
- [x] T058 Update `docs/src/modules/server-devices.md` for terminal session
  sequencing, command-result gating, support-user SSH target, and cleanup paths.
- [x] T059 Skipped: `docs/src/modules/deployment-compose.md` already references
  `nixstasis-support` and the sshd drop-in in the correct context.
- [x] T060 Skipped: `docs/src/reference/openapi/device-api.yaml` does not contain
  stale capability or legacy `authorized_keys_path` references; the command
  schema remains intentionally generic.
- [x] T061 Update `docs/src/features/index.md` and `docs/src/SUMMARY.md` so the
  feature spec is discoverable in the mdBook.
- [x] T062 Update `packages/client/README.md` with installation/runtime notes for
  dynamic browser-terminal SSH authorization. Drop the compatibility-only
  legacy file fallback section.
- [x] T063 Skipped: `packages/server/README.md` does not describe `ssh_authorize`
  payload shapes or terminal sequencing details.
- [x] T064 `docs/src/planned-features.md` `in-memory-ssh-authorized-keys` entry
  is now marked **done** with completion notes that no capability gate or
  file-based fallback is in scope.

## Integration Verification

- [ ] T065 Run focused client unit tests for the SSH authorization store, IPC
  server, helper command, command handler, and poll/runtime lifecycle.
- [ ] T066 Run focused server tests for terminal command payloads, dynamic
  `ssh_authorize` shape, command-result gating, cleanup, and
  `nixstasis-support` SSH target behavior.
- [ ] T067 Run package/release verification that covers helper installation,
  sshd drop-in, users, socket permissions, and public-key-only login. (Legacy
  file preservation check is **cancelled**.)
- [x] T068 Run a real-sshd container integration test proving
  `AuthorizedKeysCommand` invokes the helper with `%u %t %k`, allows a
  short-lived key, and denies it after TTL expiry.
- [x] T069 Run a Compose dev-lab/browser terminal smoke test that launches a
  session, runs `whoami` and verifies `nixstasis-support`, runs a safe sudo or
  run0 diagnostic command, closes the session, and verifies expired-key denial.
- [ ] T070 Run documentation validation for changed mdBook pages and OpenAPI
  validation for the device command schema.
- [ ] T071 Search code and docs for stale browser-terminal `authorized_keys`
  guidance, the heartbeat `capabilities` field, and the legacy
  file-based `runtime.authorized_keys_path` field. Reconcile any remaining
  references with the in-memory-only story.

## Parallelization Notes

- [x] T072 **cancelled.** The capability / wire-contract section (old T004-T008)
  no longer exists. The remaining doc/test/packaging work is small enough to
  land in a single focused pass.
- [x] T073 Keep formatting and verification gates single-run at the end of the
  implementation branch to avoid redundant formatter/test churn across parallel
  edits.

## Completion

- [ ] T999 Confirm implementation, packaging, docs/contracts, and tests agree;
  ensure no default, generated config, package script, or runtime path
  persists browser-terminal public keys in any `authorized_keys` file or sends a
  `capabilities` field on the heartbeat, and summarize the final scope.
