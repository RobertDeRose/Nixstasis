# In-Memory SSH Authorized Keys Tasks

## Setup

- [x] T000 Confirm the active worktree is
  `feat/in-memory-ssh-authorized-keys` and the feature spec matches the intended
  `in-memory-ssh-authorized-keys` brief.
- [ ] T001 Read `packages/AGENTS.md`, `packages/client/AGENTS.md`, and
  `packages/server/AGENTS.md` before changing package files.
- [x] T002 Inventory current browser-terminal SSH flow across server terminal
  session creation, `ssh_authorize` command delivery, heartbeat serialization,
  client command handling, packaging, and docs.
- [x] T003 Reconcile `docs/src/planned-features.md` on this branch with the
  reviewed feature spec if the planned feature entry is absent or stale.

## Contract Foundation

- [ ] T004 Define the heartbeat capability contract in code and docs as
  `capabilities: ["ssh_authorize_dynamic_v1"]`.
- [ ] T005 Extend the Go client heartbeat request type and transport tests so the
  client advertises `ssh_authorize_dynamic_v1` on every poll.
- [ ] T006 Extend Phoenix heartbeat parameter handling and tests so authenticated
  heartbeat capabilities update a latest-observed dynamic-auth compatibility gate
  with heartbeat-freshness expiry.
- [ ] T007 Update `HeartbeatJSON.command_data/1` or the command contract so the
  exact JSON sent by `POST /api/v1/devices/:id/heartbeat` includes the public key
  in the place consumed by the Go client.
- [ ] T008 Add server/client contract tests for dynamic-capable, absent, unknown,
  stale, and long-offline heartbeat capability cases.

## Client Authorization Store And IPC

- [ ] T009 Add a client internal SSH authorization package for in-memory key
  entries keyed by canonical key material/fingerprint and target Unix user.
- [ ] T010 Implement authorization store add, match, expiry, revoke by command id
  or session ref, and restart-empty initialization behavior.
- [ ] T011 Reject malformed public keys before storage and normalize valid keys
  before comparison.
- [ ] T012 Add unit tests for store allow, unknown key denial, wrong-user denial,
  malformed-key rejection, expiry, explicit revoke, and empty store after restart.
- [ ] T013 Implement a local Unix-domain IPC server under `/run/nixstasis/` for
  SSH authorization lookups.
- [ ] T014 Bound IPC request and response sizes and enforce short lookup
  deadlines.
- [ ] T015 Implement stale-socket cleanup only for Unix sockets at the expected
  path.
- [ ] T016 Ensure IPC socket permissions allow only the client runtime identity
  and `nixstasis-ssh-authority` helper identity to communicate.
- [ ] T017 Add IPC server tests for allow, deny, malformed request, oversized
  request, invalid method/payload, timeout/cancellation, missing/removed socket,
  and stale-socket handling where practical.

## Helper Command

- [ ] T018 Add `/usr/libexec/nixstasis/ssh-authorized-keys` as a small Go helper
  command or installed client subcommand.
- [ ] T019 Make the helper accept exactly `<unix-user> <key-type>
  <base64-key-blob>` from OpenSSH `%u %t %k` and reject invalid argument counts,
  key types, or oversized key input without contacting IPC.
- [ ] T020 Make the helper query the local Unix socket with `user`, `key_type`,
  and `key_blob`, then print `<key-type> <base64-key-blob>` only for an explicit
  allow response.
- [ ] T021 Make helper denial paths print no stdout for unknown, expired,
  malformed, wrong-user, timeout, invalid-response, and client-unavailable cases.
- [ ] T022 Add helper tests with a fake Unix socket server covering allow, deny,
  timeout, invalid response, missing socket, malformed OpenSSH argv, wrong user,
  and oversized input.

## Client Command Handling And Runtime

- [ ] T023 Extend `ssh_authorize` command parsing to accept dynamic auth payloads
  with target user, TTL, session ref, and public key.
- [ ] T024 Store dynamic `ssh_authorize` keys in memory instead of appending to
  `authorized_keys`.
- [ ] T025 Preserve the existing file-based `authorized_keys_path` handling only
  as an explicitly configured compatibility branch for legacy payloads.
- [ ] T026 Remove new-install defaults and example configuration that make
  `runtime.authorized_keys_path` appear to be the normal browser-terminal path.
- [ ] T027 Return safe command-result metadata for dynamic authorization without
  leaking key material.
- [ ] T028 Start and stop the SSH authorization IPC server with the client poll
  runtime lifecycle.
- [ ] T029 Add client command-handler tests for dynamic auth success, malformed
  payloads, invalid TTL, wrong target user, legacy file fallback, and command
  result metadata.
- [ ] T030 Add poll/runtime tests proving the IPC server is available while the
  client is running and unavailable after shutdown.

## Server Terminal Contract

- [ ] T031 Change terminal session startup to create the server terminal session
  ref before queueing `ssh_authorize` so the queued command can carry the ref.
- [ ] T032 Queue dynamic terminal authorization commands with public key, target
  user `nixstasis-support`, TTL, and session metadata.
- [ ] T033 Render queued browser-terminal `ssh_authorize` commands only for
  clients with a fresh latest-observed `ssh_authorize_dynamic_v1` capability.
- [ ] T034 Return an operator-visible upgrade-required terminal-start failure for
  absent, unknown, or stale dynamic-auth capability instead of queueing a legacy
  browser-terminal command.
- [ ] T035 Change the server SSH client destination user from `nixstasis` to
  `nixstasis-support`.
- [ ] T036 Gate browser terminal token activation on an OK `ssh_authorize` command
  result for dynamic clients.
- [ ] T037 Clear server-side terminal session refs on queue failure, authorization
  failure, acknowledgement timeout, join failure, terminal close, and expiry.
- [ ] T038 Add server tests for dynamic `ssh_authorize` payload shape, TTL bounds,
  target user, session ref, fresh/stale capability behavior, upgrade-required
  failures, heartbeat public-key serialization, and omission of
  `authorized_keys_path`.
- [ ] T039 Add server tests for terminal sequencing, queue-failure cleanup,
  command-result gating, timeout cleanup, and SSH destination user.
- [ ] T040 Add or update terminal close/revoke behavior if an existing command or
  server hook can explicitly revoke client-side in-memory authorization.

## Packaging And Runtime Contract

- [ ] T041 Install the helper at
  `/usr/libexec/nixstasis/ssh-authorized-keys` with root-owned, non-writable
  permissions.
- [ ] T042 Add an sshd config drop-in for `nixstasis-support` using
  `PubkeyAuthentication yes`, `AuthenticationMethods publickey`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no` or compatible
  older OpenSSH spelling, `AuthorizedKeysFile none`, `AuthorizedKeysCommand`, and
  `AuthorizedKeysCommandUser nixstasis-ssh-authority`.
- [ ] T043 Create or update the `nixstasis-support` operator account in package
  install scripts without deleting existing operator-owned SSH state.
- [ ] T044 Create or update locked `nixstasis-ssh-authority` as the OpenSSH helper
  identity and ensure it does not receive sudo/run0 repair privileges.
- [ ] T045 Create a socket-access group and ensure the client runtime identity and
  `nixstasis-ssh-authority` can use it for IPC.
- [ ] T046 Ensure `/run/nixstasis/` is mode `0750` and the socket is mode `0660`
  with ownership that permits only the client runtime and helper identity.
- [ ] T047 Prefer systemd `RuntimeDirectory=nixstasis` cleanup for managed client
  service runs and test stale socket cleanup for non-systemd/fallback runs.
- [ ] T048 Safely reload or restart sshd from package install scripts when systemd
  is available.
- [ ] T049 Extend release/package verification to assert helper path, sshd drop-in,
  support user, authority user, socket group/modes, sudo/run0 separation,
  public-key-only support login, legacy file preservation, and no new-install
  browser-terminal `authorized_keys` dependency.
- [ ] T050 Add container packaging or integration coverage for the sshd drop-in on
  supported Linux targets where practical.

## Documentation

- [ ] T051 Update `docs/src/client-server-interface.md` for heartbeat
  capabilities, the dynamic `ssh_authorize` payload, public-key serialization,
  upgrade-required behavior for clients without dynamic auth, and compatibility
  limits.
- [ ] T052 Update `docs/src/data-flow.md` for the browser-terminal flow:
  session-ref creation before queueing, command-result gating, OpenSSH helper,
  Unix IPC, and in-memory authorization.
- [ ] T053 Update `docs/src/runtime-boundaries.md` to document the Phoenix/Caddy,
  FRP, OpenSSH, helper, IPC, and client memory boundaries.
- [ ] T054 Update `docs/src/modules/client-command-handler.md` for dynamic
  `ssh_authorize`, legacy fallback, and safe command-result metadata.
- [ ] T055 Update `docs/src/modules/client-transport.md` for heartbeat
  capabilities and the final command request/response structs.
- [ ] T056 Update `docs/src/modules/client-frp-manager.md` if poll/runtime
  lifecycle ownership changes while starting the SSH authorization IPC server.
- [ ] T057 Update `docs/src/modules/edge-frp.md` for the unchanged FRP route and
  changed SSH key authorization boundary.
- [ ] T058 Update `docs/src/modules/server-devices.md` for terminal session
  sequencing, command-result gating, support-user SSH target, and cleanup paths.
- [ ] T059 Update `docs/src/modules/deployment-compose.md` for installed helper,
  sshd drop-in, support account, authority account, and socket permissions.
- [ ] T060 Update `docs/src/reference/openapi/device-api.yaml` for heartbeat
  capabilities, the dynamic `ssh_authorize` command schema, and documented
  compatibility-only legacy command parsing.
- [ ] T061 Update `docs/src/features/index.md` and `docs/src/SUMMARY.md` so the
  feature spec is discoverable in the mdBook.
- [ ] T062 Update `packages/client/README.md` with installation/runtime notes for
  dynamic browser-terminal SSH authorization and compatibility-only legacy file
  fallback.
- [ ] T063 Update `packages/server/README.md` if server terminal command behavior
  or local development setup changes.
- [ ] T064 Update `docs/src/planned-features.md` with accurate implementation
  status and completion notes after the feature lands.

## Integration Verification

- [ ] T065 Run focused client unit tests for transport capabilities, SSH
  authorization store, IPC server, helper command, command handler, and
  poll/runtime lifecycle.
- [ ] T066 Run focused server tests for terminal command payloads,
  capability-based heartbeat serialization, command-result gating, cleanup, and
  `nixstasis-support` SSH target behavior.
- [ ] T067 Run package/release verification that covers helper installation,
  sshd drop-in, users, socket permissions, public-key-only login, and legacy file
  preservation.
- [ ] T068 Run a real-sshd container integration test proving
  `AuthorizedKeysCommand` invokes the helper with `%u %t %k`, allows a
  short-lived key, and denies it after TTL expiry.
- [ ] T069 Run a Compose dev-lab/browser terminal smoke test that launches a
  session, runs `whoami` and verifies `nixstasis-support`, runs a safe sudo or
  run0 diagnostic command, closes the session, and verifies expired-key denial.
- [ ] T070 Run documentation validation for changed mdBook pages and OpenAPI
  validation for the device command schema.
- [ ] T071 Search code and docs for stale browser-terminal `authorized_keys`
  guidance and reconcile any remaining references with the compatibility story.

## Parallelization Notes

- [ ] T072 After T004-T008 define the shared wire contract, client store/helper,
  server terminal contract, packaging, and documentation work can proceed in
  parallel as long as implementers coordinate on the final command JSON and
  helper IPC structs.
- [ ] T073 Keep formatting and verification gates single-run at the end of the
  implementation branch to avoid redundant formatter/test churn across parallel
  edits.

## Completion

- [ ] T999 Confirm implementation, packaging, docs/contracts, and tests agree;
  ensure no new-install default, generated config, package script, or runtime path
  persists browser-terminal public keys in any `authorized_keys` file as the
  normal authorization path, and summarize any intentional legacy compatibility
  left in place.
