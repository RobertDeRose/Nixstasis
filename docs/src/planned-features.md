# Planned Features

This page is the human-readable roadmap. During migration, legacy status and task evidence remain here; after import,
Beads is authoritative for live status, dependencies, claims, and ready-work selection.

## Project Overview

Nixstasis needs a Compose development harness that exercises the same remote-access
boundaries operators rely on in deployment. Local development must be able to test
dynamic TLS approval and browser-driven SSH terminal flows without waiting for a
production-like environment.

Nixstasis also needs a server-managed Stary script lifecycle so operators can
author, validate, test, and deploy telemetry scripts from the web interface
instead of relying only on client-local CLI workflows.

Because Stary scripts can call `exec_cmd`, Nixstasis needs server-managed command
allowlist policies that operators can compose into categories and assign to
specific devices before those scripts are allowed to execute host commands.

Operators also need first-class device groups in the Dashboard Devices view so
they can organize fleets by operational ownership, location, role, or rollout
cohort instead of relying only on product, account, status, and search filters.

## Goals

- Provide a repeatable Compose development harness for end-to-end remote-access
  validation.
- Make Caddy on-demand TLS approval testable from local development workflows.
- Make UI-launched SSH terminal sessions testable from local development workflows.
- Keep the development workflow aligned with documented runtime boundaries for
  Phoenix, Caddy, FRPS, FRPC, and managed-device identity.
- Support an optional public-fidelity mode using DuckDNS or a real operator-owned
  domain when developers need to validate public ACME behavior.
- Provide a browser-based workflow for developing Stary scripts, editing
  front-matter metadata, validating syntax and schema declarations, and testing
  candidate scripts against selected managed clients before deployment.
- Provide a browser-based workflow for defining command execution allowlists,
  grouping them into reusable categories, and assigning the resulting policy to
  selected devices.
- Provide a Devices view workflow for creating, editing, filtering by, and
  assigning operator-managed device groups.

## Non-Goals

- Replacing the supported production Compose deployment path.
- Changing production TLS policy or public ingress requirements.
- Building a full hosted staging environment.
- Making local development depend on public DNS or public certificate issuance when
  a local equivalent can validate the same application behavior.
- Requiring ngrok, localtunnel, or another third-party tunnel provider for the
  default development workflow.
- Replacing the client-side Stary runtime, script parser, schema validator, or
  CLI workflows that already support local development.
- Treating server-side script tests as a substitute for client-side runtime
  enforcement during normal polling.
- Turning `exec_cmd` into a general remote shell, arbitrary command runner, or
  package-management framework.
- Allowing scripts to grant themselves additional command execution permissions.
- Treating product name, account number, approval status, or ad hoc search
  filters as a complete replacement for durable operator-managed groups.

## Global Constraints

- The supported production deployment path remains `deploy/compose`.
- Development overrides should use Compose file composition, not mutable release
  image tags in `.env`.
- The Phoenix application remains public only through Caddy in deployment-shaped
  flows.
- SSH terminal testing must exercise the browser UI, Phoenix Channels, server-side
  SSH process boundary, and FRP TCP mux path rather than bypassing them with direct
  shell access.
- TLS testing must exercise `GET /api/v1/check_domain` approval behavior.
- Default laptop mode uses Caddy's internal CA/local certificates and local host
  routing so development does not require public DNS or public ingress.
- Optional public-fidelity mode may use DuckDNS or a real domain with DNS-based
  ACME validation to test publicly trusted certificate behavior.
- The server web interface may orchestrate Stary validation and test execution,
  but clients remain the authoritative execution environment for runtime behavior
  and builtin availability.
- Server-managed script deployment must be auditable and scoped to explicit
  client selections, groups, or future targeting rules rather than silently
  changing every managed client.
- Server-managed command allowlists must remain deny-by-default, use explicit
  absolute executable paths, and be resolved into device-local runtime policy
  before a Stary script can execute `exec_cmd`.
- Composed allowlist categories are additive only in the first version; removing
  or narrowing permissions requires changing the assigned category or device
  policy rather than relying on hidden precedence rules.
- Device groups are operator-managed fleet organization records, not a source of
  device identity. Registration and heartbeat authentication continue to depend
  on device identity, approval state, and API tokens.

## Cross-Cutting Decisions

- Treat local dynamic TLS and UI SSH validation as one development-environment
  feature because both depend on the same local ingress, DNS/host routing, FRPS,
  and device-client simulation shape.
- Default development mode uses local-only trust and routing mechanisms instead of
  public DNS or real public certificate issuance.
- DuckDNS or a real domain is an optional validation path for public ACME fidelity,
  not a prerequisite for local feature development.
- Keep production Compose docs and Compose dev-harness docs explicitly separated so
  test affordances do not become accidental production guidance.
- Treat server-side Stary authoring as a new script-management feature layered on
  top of the completed client-local Starlark script system.
- Validate front matter and Starlark syntax before dispatching tests to clients,
  while still requiring selected clients to execute test runs so builtin,
  environment, timeout, and output-schema behavior matches reality.
- Keep server-managed Stary authoring, command allowlist management, and device
  groups as independent feature tracks. They may integrate later, but each should
  be specifiable, implementable, and testable on its own.
- The command policy UI can call entries "whitelists" for operator familiarity,
  but implementation docs use "allowlist" for consistency with the existing
  `exec_cmd` runtime boundary.

## Resolved Questions

- The managed test device runs as a containerized client with systemd, sshd, frpc,
  and the Go client binary — matching real device lifecycle.
- Reserved local hostnames: `nixstasis.localhost`, `auth.localhost`,
  `frp-admin.localhost`, and `atom-<normalized-device-id>.localhost`.
- Terminal smoke test covers session open, command execution, session close, and
  reopen via ExUnit LiveView integration test with a fake SSH client.
- DuckDNS support is documented as optional manual setup guidance; no DNS-provider
  abstraction was added.

## Backlog

- Move bespoke Phoenix controller APIs under Ash-backed actions/resources where
  practical so their OpenAPI contracts can be generated from the same source of
  truth as the `/api/json` surface.
- Completed: production AuthCrunch/Phoenix role and claim contract, including
  header mapping, LiveView authorization behavior, and operator role semantics.
- Completed: production operations runbooks for backup/restore, secret rotation,
  incident response, HA expectations, and production monitoring.
- Completed: richer API examples for common success, validation-error,
  authorization, and edge-case responses across maintained API contracts.

## Feature Map

### Compose dev harness (`compose-dev-harness`)

- Status: completed
- Overview:
- Create a default Compose development harness that can run the server-side stack,
  register or simulate a managed client, validate Caddy dynamic TLS approval with
  local certificates, and open SSH terminal sessions from the Phoenix UI through
  the FRP path. Add optional guidance for DuckDNS or a real domain when public
  ACME fidelity is required.
- Requirements:
- Provide documented startup and teardown commands for the local development
  environment.
- Provide local host routing/DNS guidance for the app host, AuthCrunch host,
  FRPS admin host, and device wildcard hostnames.
- Provide a local TLS validation path that exercises Caddy on-demand approval via
  Phoenix `GET /api/v1/check_domain` using Caddy internal CA/local certificates
  by default.
- Provide optional DuckDNS or real-domain guidance for validating public ACME
  behavior without making that path required for normal development.
- Provide a test managed-device path that can register, connect FRPC to FRPS, and
  expose SSH in a way the UI terminal can reach.
- Provide validation steps for opening a terminal from `/devices/:id` and running
  a harmless command through the browser UI.
- Document how the development workflow differs from production Compose.
- Constraints:
- Must not weaken or bypass production ingress/authentication requirements.
- Must not require public DNS or public internet exposure for the core local
  validation path.
- Must keep DuckDNS and real-domain support optional and clearly marked as
  public-fidelity validation.
- Must preserve Compose-file-composition as the development override mechanism.
- Must keep generated certificates, local keys, and runtime state out of source
  control.
- Non-goals:
- Making production certificate issuance validation mandatory for local
  development.
- Multi-user staging operations.
- Load, performance, or HA validation.
- Replacing existing E2E API protocol validation.
- Success criteria:
- A developer can start the local stack from a clean checkout using documented
  commands and local-only configuration.
- Visiting the local app through Caddy with local certificates causes TLS approval
  behavior to be exercised and observable.
- Optional DuckDNS or real-domain instructions identify how to run a higher
  fidelity public ACME validation path and how it differs from default laptop
  mode.
- A test device appears in the UI with remote-access state sufficient to launch
  a terminal.
- A browser-launched terminal session can run a harmless command through FRP and
  SSH without direct shell shortcuts.
- The docs clearly separate development-only shortcuts from production deployment
  guidance.
- Risks and tradeoffs:
- Local TLS can become misleading if it validates only certificate plumbing and
  not domain approval behavior.
- Device simulation can hide real packaging/client defects if it bypasses the Go
  client and FRPC process model.
- Hostname routing can become fragile across macOS, Linux, Docker, Podman, and
  Apple Container unless the spec chooses supported paths explicitly.
- Using real public DNS would increase fidelity but adds cost, secrets, and
  operational burden for developers.
- DuckDNS reduces domain cost but adds account tokens, DNS propagation delay, and
  external-service availability concerns.
- Tunnel providers such as ngrok or localtunnel are useful for reachability demos
  but can mask Caddy-owned TLS behavior if they terminate TLS before Caddy.
- Dependencies:
- `deploy/compose/docker-compose.yml`
- `deploy/compose/caddy/Caddyfile`
- `deploy/compose/frps/frps.toml`
- `packages/server/lib/nixstasis_web/controllers/tls_controller.ex`
- `packages/server/lib/nixstasis_web/channels/terminal_channel.ex`
- `packages/server/lib/nixstasis/devices/ssh_client.ex`
- `packages/client/internal/frp/manager.go`
- `packages/client/cmd/nixstasis/register.go`
- `packages/client/cmd/nixstasis/poll.go`
- Suggested validation:
- Static validation for generated Compose development overrides.
- A local smoke test that confirms Caddy reaches Phoenix TLS approval.
- A local smoke test that confirms Caddy serves local certificates through the
  default laptop hostnames.
- A local smoke test that confirms FRPC connects to FRPS using the development
  configuration.
- Optional DuckDNS or real-domain validation that documents certificate issuance,
  DNS challenge behavior, and expected failure modes.
- A browser/UI or E2E journey that launches a terminal and executes a harmless
  command through SSH.
- Suggested first workflow command: `/start-feature compose-dev-harness`

### Self extracting installer (`self-extracting-installer`)

- Status: completed
- Overview:
- Build a CI-produced self-extracting installer archive for non-Nix, non-deb,
  non-rpm installs. The archive bundles the client binary, arch-matched `frpc`,
  configs, systemd units, and an artifact manifest into a single `.run` file
  that extracts and installs to FHS paths.
- Requirements:
- Produce a self-extracting archive per supported architecture as part of the
  client release workflow.
- Include an install script that copies files to `/usr/bin/`,
  `/usr/libexec/nixstasis/`, `/etc/nixstasis/`,
  `/usr/share/nixstasis/`, and `/lib/systemd/system/`.
- Include an `artifacts.json` manifest with version, arch, sha256 per file,
  file modes, and build timestamp.
- Consume `frpc` from `packages/frp` via the shared acquisition path, not a
  separate download.
- Extend client release CI so `.run` files are produced and verified alongside
  existing archives, `.deb`, and `.rpm` packages.
- Extend `verify_artifacts.sh` to validate `.run` archive contents and
  manifest integrity.
- Constraints:
- Do not embed `frpc` in the Go client binary.
- `FRPS_SERVER_ADDR` remains a runtime env var, not baked into the archive.
- Systemd units must use `PrivateTmp=true`.
- `build/root-dir` stays as the GoReleaser staging source.
- `packages/frp` remains the shared source of truth for FRP version and
  checksums.
- Non-goals:
- Replacing `.deb` or `.rpm` packaging for distros that support them.
- Interactive TUI installer or configuration wizard.
- Automatic service enablement or start on install.
- Uninstall support.
- Success criteria:
- A `.run` file for each release architecture is published to GitHub Releases.
- Running the `.run` file on a clean Linux system installs all required files
  to their FHS paths.
- Existing `/etc/nixstasis/config.yaml` is preserved on upgrade unless the
  installer is explicitly forced to replace it; client-owned `frpc.toml` is
  updated on every upgrade from `/usr/share/nixstasis/frpc.toml`.
- `artifacts.json` in the archive matches the installed bundle contents by
  sha256.
- `verify_artifacts.sh` catches content or manifest drift in CI.
- Risks and tradeoffs:
- `makeself` adds a release CI dependency.
- Self-extracting archives are less auditable than plain tarballs, so the
  installer must support no-exec extraction for inspection.
- Install script upgrade behavior must avoid overwriting operator-owned config.
- Dependencies:
- `packages/frp/bin/download_frp.sh`
- `packages/client/build/bin/fetch_frpc.sh`
- `.github/workflows/release_client.yml`
- `packages/client/build/bin/verify_artifacts.sh`
- `packages/client/build/root-dir/`
- `prod.env`
- Suggested validation:
- CI step that builds the `.run` archive from snapshot artifacts and verifies
  extraction plus manifest integrity.
- Fresh-install and upgrade tests for file placement, modes, and config
  preservation.
- Manual smoke test on Alpine or Arch to confirm FHS placement without
  `dpkg`/`rpm`.
- Suggested first workflow command: `/start-feature self-extracting-installer`

### Server provided frps token (`server-provided-frps-token`)

- Status: completed
- Overview:
- Move the remote-access trigger from a boolean heartbeat response flag to a
  server-provided FRPS auth token. When the server wants a client to open
  remote access, the heartbeat response includes the shared FRPS token. The
  client treats the presence of that token as the start signal, passes it to
  the transient unit through a systemd credential, and stops FRPC when the
  token is absent.
- Requirements:
- Replace `remote_access_requested` in the device heartbeat response contract
  with `remote_access_token`.
- Include `remote_access_token` only when remote access is currently requested
  for the device.
- Make the Phoenix server read the shared FRPS token from deployment
  configuration and expose it only to authenticated device heartbeat responses
  that need remote access.
- Make the Compose `nixstasis` service receive the same `FRPS_AUTH_TOKEN` as
  the `frps` service.
- Make the Go client start FRPC when `remote_access_token` is non-empty and
  use that value as `FRPS_AUTH_TOKEN` for frpc template expansion.
- Make the Go client stop FRPC when `remote_access_token` is absent or empty.
- Keep the device runtime API token separate from the FRPS auth token.
- Constraints:
- The current FRPS deployment uses upstream FRP token auth with one shared
  `FRPS_AUTH_TOKEN`.
- Do not add an FRPS authentication plugin or per-device FRPS tokens in this
  feature.
- Do not persist the FRPS token in client config or identity files.
- The client-owned `frpc.toml` continues to use `{{ .Envs.FRPS_AUTH_TOKEN }}`
  and frpc-native environment expansion.
- The client continues launching FRPC through the `nixstasis-frpc` transient
  systemd unit.
- Non-goals:
- Replacing FRP token authentication.
- Implementing per-device FRPS auth or revocation.
- Changing browser terminal authorization.
- Changing how operators request or close remote access in the UI beyond the
  heartbeat response payload.
- Success criteria:
- A heartbeat for a device without requested remote access returns no FRPS
  token and the client stops or leaves FRPC stopped.
- A heartbeat for a device with requested remote access returns the configured
  FRPS token and the client starts FRPC with that token in the transient unit
  credential path.
- The device API token is never used as the FRPS token.
- Server and client tests cover both token-present and token-absent response
  paths.
- Runtime contract documentation identifies `FRPS_AUTH_TOKEN` as consumed by
  both `frps` and `nixstasis`.
- Risks and tradeoffs:
- Returning a shared FRPS token to a device exposes that token to the managed
  host during the active remote-access lease.
- A shared token keeps FRPS deployment simple but cannot revoke a single
  device independently at the FRPS layer.
- If `FRPS_AUTH_TOKEN` is missing from the server environment while remote
  access is requested, clients cannot open FRPC even though the UI requested
  access.
- Dependencies:
- `packages/server/lib/nixstasis_web/controllers/heartbeat_json.ex`
- `packages/server/test/nixstasis_web/controllers/heartbeat_controller_test.exs`
- `packages/client/internal/transport/client.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/cmd/nixstasis/poll_test.go`
- `packages/client/internal/frp/manager.go`
- `deploy/compose/docker-compose.yml`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `docs/src/client-server-interface.md`
- `docs/src/modules/deployment-compose.md`
- Suggested validation:
- Server controller tests for `remote_access_token` omitted when remote access
  is false and present when true with `FRPS_AUTH_TOKEN` configured.
- Client transport/poll tests for starting FRPC with heartbeat-provided token.
- Client poll tests for stopping FRPC when the token is absent.
- Runtime contract check proving the Phoenix service receives
  `FRPS_AUTH_TOKEN`.
- Suggested first workflow command: `/start-feature server-provided-frps-token`

### In memory ssh authorized keys (`in-memory-ssh-authorized-keys`)

- Status: delivered
- Overview:
- Replace file-based browser-terminal SSH key authorization with an OpenSSH
  `AuthorizedKeysCommand` integration backed by the Go client runtime. The
  server still issues short-lived ephemeral terminal keys, but the managed
  device stores those keys in memory only. When `sshd` needs to authenticate a
  browser terminal session for the dedicated support account, a small helper
  asks the running Nixstasis client over local IPC whether the offered key is
  currently authorized. This avoids writing operator SSH keys to disk and keeps
  support access independent from the `nixstasis` service account's filesystem
  permissions. The dynamic `ssh_authorize` payload is the only path the server
  emits; there is no capability gate and no file-based fallback.
- Background and problem statement:
- Browser terminal access currently targets a dedicated `nixstasis-support`
  account so operators can diagnose and repair devices using tools such as
  `sudo systemctl`, `run0 systemctl`, package managers, journal logs, and
  system status commands.
- The `nixstasis` account should remain the service identity for the client
  process and should not be the account operators SSH into for repairs.
- A file-based `authorized_keys` design requires the client process to write to
  `/var/lib/nixstasis-support/.ssh/authorized_keys`.
- If the client runs as root, file writes work but broaden the client daemon's
  privilege boundary.
- If the client later runs as the unprivileged `nixstasis` user, it cannot write
  keys owned by `nixstasis-support` unless a privileged helper or sudo rule is
  introduced.
- OpenSSH already supports dynamic key lookup through `AuthorizedKeysCommand`,
  which lets the client keep ephemeral keys in memory and answer key lookup
  requests at authentication time.
- Requirements:
- Configure `sshd` for the support account so it does not use a persistent
  `authorized_keys` file for browser-terminal keys.
- Add an OpenSSH config snippet equivalent to:
  `Match User nixstasis-support`, `AuthorizedKeysFile none`,
  `AuthorizedKeysCommand /usr/libexec/nixstasis/ssh-authorized-keys %u %t %k`,
  and `AuthorizedKeysCommandUser nixstasis-ssh-authority`.
- Add a locked-down `nixstasis-ssh-authority` system user for running the helper;
  it must not be the `nixstasis-support` operator account.
- Add a small helper binary or command at
  `/usr/libexec/nixstasis/ssh-authorized-keys`.
- The helper must accept the OpenSSH-supplied username and public key, ask the
  local client runtime over IPC/RPC whether that key is currently authorized,
  print the public key to stdout only when authorized, and print nothing when
  denied or unavailable.
- The Go client must maintain an in-memory set of ephemeral SSH public keys with
  metadata such as target user, command/session id, issued time, expiry time,
  and optional device/session context.
- The Go client must expose a local-only IPC endpoint at the fixed Unix-domain
  socket `/run/nixstasis/ssh-authority.sock` for the helper to query current SSH
  key authorization state.
- The IPC socket must have strict permissions so only the helper identity and the
  client runtime can access it.
- The client must enforce key TTL and remove keys after expiry, explicit terminal
  close, command/session completion where possible, or client restart.
- The server's `ssh_authorize` command should deliver the ephemeral public key
  and TTL/session context to the client without requiring an
  `authorized_keys_path`.
- The server-side SSH client must continue to connect as `nixstasis-support` for
  browser terminal sessions.
- The support account must support privileged diagnostics and repair through both
  `sudo` and systemd `run0`, while the dynamic key helper remains narrow and
  only answers key lookups.
- Constraints:
- Do not grant broad sudo to the `nixstasis` service account just so it can edit
  `nixstasis-support` SSH files.
- Do not persist ephemeral browser-terminal public keys in
  `/var/lib/nixstasis-support/.ssh/authorized_keys` for new installs.
- Do not make the helper perform arbitrary client commands; it only answers
  whether an offered key is authorized.
- Do not expose the IPC endpoint on TCP or any non-local network interface.
- Do not let the helper trust user-controlled paths or write files based on SSH
  login input.
- Keep browser/operator authorization in Phoenix/Caddy separate from device-side
  SSH key authorization. A key is valid only after the server has authorized the
  operator and sent the device an `ssh_authorize` command.
- Keep support-user SSH access separate from FRP token distribution; FRP opens
  the route, while this feature decides whether a public key may authenticate.
- Non-goals:
- Replacing FRP or changing the FRPS TCP mux route.
- Implementing a general-purpose remote shell daemon outside OpenSSH.
- Supporting password-based support login.
- Implementing permanent operator SSH keys or long-lived device-local user
  accounts for every operator.
- Building a full privileged command execution framework.
- Proposed runtime flow:
- Operator clicks Start Remote Session in the Phoenix UI.
- Server generates an ephemeral SSH key pair and queues `ssh_authorize` for the
  device with the public key, target user `nixstasis-support`, and a short TTL.
- Client receives the command during polling and stores the public key in memory
  only.
- The server waits for the matching `ssh_authorize` command result to be `OK`,
  then exposes the terminal socket token and opens the browser terminal channel.
- The server starts `ssh` through FRP as `nixstasis-support@atom-<device>-ssh`.
- Device `sshd` receives the public-key authentication attempt and invokes
  `/usr/libexec/nixstasis/ssh-authorized-keys %u %t %k` as
  `nixstasis-ssh-authority`.
- The helper sends the username and offered key to the client IPC socket.
- The client checks the in-memory authorization set, TTL, and target user.
- If authorized, the helper prints the matching public key to stdout and exits
  successfully; OpenSSH continues login.
- If not authorized, expired, or the client is unavailable, the helper prints
  nothing and OpenSSH denies the key.
- When the terminal closes or fails, the server clears its private key material
  and queues an idempotent `ssh_revoke` command with
  `application/vnd.nixstasis.ssh-revoke+json;version=1`; independently, the
  client expires the key by TTL.
- Packaging and installer requirements:
- Client installers must create or update `nixstasis-support` for operator SSH
  sessions.
- Client installers must create or update `nixstasis-ssh-authority` as a locked
  system user for `AuthorizedKeysCommandUser`.
- Client installers must install the helper under `/usr/libexec/nixstasis/` with
  root-owned, non-writable permissions.
- Client installers must install an sshd config drop-in for the support user and
  reload/restart sshd safely when systemd is available.
- Client installers must ensure `/run/nixstasis/` runtime ownership and mode allow
  the client daemon and helper to communicate but do not expose the socket to
  untrusted local users.
- If package upgrades find an old file-based
  `/var/lib/nixstasis-support/.ssh/authorized_keys`, they should preserve it
  unless the design explicitly defines cleanup; avoid deleting operator-owned
  keys unexpectedly.
- Migration and compatibility notes:
- The dynamic `ssh_authorize` and `ssh_revoke` payloads are the only paths. There
  is no `runtime.authorized_keys_path` runtime config and no file-based fallback
  for browser-terminal SSH keys.
- Server command payloads do not need a compatibility shape: the dynamic JSON
  payload is the only `ssh_authorize` shape the server emits, and the Go client
  always writes offered keys into its in-memory store.
- No per-device capability reporting is required. The server treats every
  authenticated device as dynamic-capable for terminal authorization.
- The client persists no keys across restart, so restart invalidates sessions.
- Security considerations:
- The helper must be small, deterministic, and auditable because OpenSSH invokes
  it during authentication.
- The helper must bound request size and timeout quickly if the client IPC socket
  is missing or unresponsive.
- The client should compare canonical public-key values, not raw unbounded input,
  and should reject malformed key material before adding it to memory.
- The IPC protocol should include the requested Unix username and public key; it
  should not authorize keys for users other than `nixstasis-support` unless the
  feature explicitly expands scope later.
- Logging must be useful for diagnosis but must not leak private key material.
  Logging public-key fingerprints is acceptable; logging full keys should be
  considered carefully.
- Password authentication should remain disabled for support SSH access.
- `nixstasis-support` may have passwordless sudo and/or polkit/run0 privileges
  for repair workflows, but this feature must not grant broad sudo or run0
  privileges to the dynamic-key helper.
- Success criteria:
- A browser terminal session authenticates to `nixstasis-support` without creating
  or modifying `/var/lib/nixstasis-support/.ssh/authorized_keys`.
- The client can run as an unprivileged service user and still authorize support
  SSH logins through the helper/IPC path.
- Expired, revoked, unknown, malformed, or wrong-user keys are denied by printing
  no authorized keys.
- Restarting the client invalidates in-memory terminal keys.
- Operators can run repair commands through both supported privilege paths, such
  as `sudo systemctl status nixstasis-poll.service`,
  `run0 systemctl status nixstasis-poll.service`, `journalctl`, and package
  manager commands after logging in as `nixstasis-support`.
- Tests prove the helper handles allow, deny, timeout, malformed-key, wrong-user,
  and client-unavailable cases.
- Tests prove the server still targets `nixstasis-support` and does not require
  `authorized_keys_path` for any client.
- Risks and tradeoffs:
- `AuthorizedKeysCommand` adds an authentication-time dependency on the local
  client process and IPC socket; if the client is down, support SSH is denied.
- Keeping keys in memory improves security but makes restart invalidate active or
  pending terminal sessions.
- OpenSSH config syntax and supported tokens vary by distro/version, so package
  tests should cover the supported Linux targets.
- A helper/IPC protocol is more complex than appending a file, but it is narrower
  and avoids broad filesystem write permissions.
- Dependencies:
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/internal/commands/handler.go`
- `packages/client/internal/config/config.go`
- `packages/client/build/root-dir/`
- `packages/client/build/debian/postinstall.sh`
- `packages/client/.goreleaser.yaml`
- `packages/server/lib/nixstasis_web/live/device_live/show.ex`
- `packages/server/lib/nixstasis/devices/ssh_client.ex`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_json.ex`
- `deploy/compose/docker-compose.yml`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `docs/src/modules/deployment-compose.md`
- `docs/src/modules/edge-frp.md`
- Suggested validation:
- Unit tests for client in-memory SSH authorization store: add, match, expiry,
  revoke, malformed key rejection, and wrong-user denial.
- Unit tests for the helper command with a fake Unix socket server covering allow,
  deny, timeout, invalid response, and missing socket.
- Integration test using a real `sshd` config in a container where
  `AuthorizedKeysCommand` authenticates a short-lived key and denies it after
  TTL expiry.
- Server tests for `ssh_authorize` payload shape and SSH target user.
- Compose dev-lab smoke test that launches a terminal, runs `whoami`, runs a sudo
  diagnostic command, closes the session, and verifies a later expired key is
  denied.
- Runtime contract checks for installed helper path, sshd drop-in, support user,
  authority user, sudoers rule, run0/polkit support, and absence of file-based
  key writes for new installs.
- Suggested first workflow command: `/start-feature in-memory-ssh-authorized-keys`

### Ash API contract unification (`ash-api-contract-unification`)

- Status: completed
- Overview:
- Rework the custom Phoenix controller APIs that represent durable product
  contracts so they are exposed through Ash actions/resources where practical,
  allowing OpenAPI generation to become the source of truth for those APIs.
  Keep explicitly workflow-only endpoints as Phoenix controllers only when Ash
  would make the contract less clear.
- Requirements:
- Inventory every externally accessed non-UI route under `/api/v1`, `/api/json`,
  `/e2e`, and related diagnostic/reference surfaces and classify it as
  `ash-backed`, `retained-controller`, `ui-only`, or `deferred`.
- Reconcile the existing builder Ash actions/generated routes and compatibility
  wrappers, then move the externally consumed device runtime to Ash-backed
  actions/resources or generated routes where the behavior maps cleanly.
- Preserve current wire contracts for the Go client, Caddy `check_domain`, and
  the current E2E harness unless a deliberate versioned contract change is
  documented.
- Generate OpenAPI docs for Ash-backed APIs and retain explicit bespoke
  contracts only for intentionally retained controllers.
- Constraints:
- Do not break existing Go client registration, heartbeat, command result, or
  command payload behavior without a versioned migration plan.
- Do not force Caddy TLS approval or current E2E workflow endpoints into Ash when
  they have no current contract benefit or a controller boundary is clearer.
- Keep report preview unchanged until a concrete external export contract exists.
- Maintain authentication and authorization semantics for device API keys,
  Caddy/AuthCrunch, bearer-protected Ash routes, and E2E enablement gates.
- Non-goals:
- Replacing Ash JSON:API with a separate OpenAPI generator.
- Converting browser LiveView routes to API routes.
- Changing the public deployment or FRP runtime contract.
- Success criteria:
- Generated OpenAPI covers every API route that is implemented as an Ash-backed
  product contract.
- Remaining bespoke OpenAPI files only document endpoints that intentionally stay
  outside Ash, with rationale in the reference docs.
- Client/server integration tests prove the Go client and E2E harness still work
  against the migrated API surface.
- The Reference section clearly distinguishes generated Ash OpenAPI from any
  retained bespoke contracts.
- Risks and tradeoffs:
- Some endpoints are protocol workflows rather than CRUD resources, and forcing
  them into Ash may obscure behavior or complicate error handling.
- Moving stable client APIs can create compatibility risk unless responses,
  status codes, and auth failures remain byte-for-byte compatible or versioned.
- Implementation status:
- Builder schema reference, option, and validation behavior now has an Ash-backed
  action resource with generated JSON:API routes under
  `/api/json/builder_contract/*` and generated OpenAPI in
  `packages/server/priv/static/openapi.yaml`.
- Legacy `/api/v1/builder-*` controller routes remain compatibility wrappers
  around the Ash actions and keep the hand-maintained wrapper contract in
  `docs/src/reference/openapi/builder-api.yaml`.
- Device runtime now has an additive Ash-backed generated contract for list,
  registration, heartbeat, command-result acknowledgement, and deferred-payload
  fetch. The Go client remains on the controller-backed `/api/v1` compatibility
  transport until a separately reviewed migration is approved.
- Caddy TLS ask and current E2E workflow remain retained controllers, report
  preview is deferred pending an export consumer, and laptop diagnostics remain
  development-only controller routes.
- Completion notes:
- The generated Ash contract boundary is delivered for builder actions and all
  five approved device-runtime actions; the Go client remains on the compatible
  `/api/v1` wrappers pending a separately reviewed client migration.
- Generated OpenAPI, compatibility references, endpoint inventory, route tests,
  and reader-facing architecture/interface docs are reconciled. The implemented
  record is `docs/src/features/ash-api-contract-unification/index.md`.
- Future report export, E2E generated-contract treatment, development diagnostics,
  and audited script-workbench actions remain separate decisions.
- Dependencies:
- `packages/server/lib/nixstasis_web/router.ex`
- `packages/server/lib/nixstasis_web/controllers/device_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/e2e_run_result_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/builder_schema_controller.ex`
- `packages/server/lib/nixstasis_web/controllers/builder_config_validation_controller.ex`
- `packages/server/lib/nixstasis/domain.ex`
- `packages/server/lib/nixstasis/devices/`
- `packages/server/lib/nixstasis/monitoring.ex`
- `packages/server/priv/static/openapi.yaml`
- `packages/client/internal/transport/`
- `packages/client/internal/e2e/`
- `docs/src/reference/openapi/`
- Suggested validation:
- Diff generated OpenAPI before/after and confirm migrated paths appear in the
  generated document.
- Run Go client transport tests and server controller/domain tests for each
  migrated route.
- Run the E2E harness against the migrated `/e2e` contract if E2E routes are
  moved or wrapped by Ash.
- Run `mdbook build docs` and ensure Reference links describe the final contract
  source of truth.
- Suggested first workflow command: `/start-feature ash-api-contract-unification`

### Authcrunch role contract (`authcrunch-role-contract`)

- Status: completed
- Overview:
- Define the production authorization contract between Caddy/AuthCrunch and the
  Phoenix application. Document which claims or headers Caddy forwards, how
  roles/groups map to operator capabilities, and whether LiveView screens use
  those claims for role-aware behavior.
- Requirements:
- Inventory AuthCrunch-related Caddy configuration, Phoenix request handling,
  LiveView session data, and any existing role/group assumptions.
- Define the canonical forwarded headers or session fields Phoenix may trust
  after Caddy/AuthCrunch authentication.
- Define operator roles and the capabilities each role grants for dashboard,
  devices, remote access, alerts, reports, settings, and E2E surfaces.
- Document behavior for missing, malformed, or insufficient claims.
- Decide whether role-aware UI behavior belongs in LiveView assigns, plugs,
  policies, or a separate authorization module.
- Update operations docs so deployment operators know which AuthCrunch groups or
  claims must be configured.
- Constraints:
- Do not weaken the requirement that public browser traffic reaches Phoenix
  through Caddy/AuthCrunch in the supported deployment.
- Do not treat device API tokens, E2E enablement, or terminal session tokens as
  substitutes for browser/operator authorization.
- Keep local development shortcuts clearly separate from production role
  enforcement.
- Non-goals:
- Replacing AuthCrunch as the browser authentication edge.
- Changing the device runtime API authentication contract.
- Implementing a full multi-tenant RBAC product unless the role inventory proves
  it is required.
- Success criteria:
- Operators can configure AuthCrunch groups/claims and know which Nixstasis
  capabilities each role enables.
- Phoenix behavior for missing or insufficient role claims is documented and
  tested.
- The docs clearly distinguish browser/operator authorization from device API,
  E2E, and terminal-session authentication.
- Risks and tradeoffs:
- Browser authorization rules can drift if they are encoded only in Caddy and not
  visible to Phoenix UI logic.
- Over-modeling roles too early can add complexity before production operator
  needs are proven.
- Completion notes:
- Caddy/AuthCrunch remains the production browser authorization edge with
  `authorize with entra_policy` on protected hosts.
- Caddy/AuthCrunch maps provider-specific OIDC groups into normalized
  `nixstasis/viewer`, `nixstasis/operator`, and `nixstasis/admin` roles before
  proxying to Phoenix.
- Phoenix maps default AuthCrunch `X-Token-*` role claim headers into device and
  report permission maps and stays provider-agnostic.
- Dependencies:
- `deploy/compose/caddy/Caddyfile`
- `packages/server/lib/nixstasis_web/router.ex`
- `packages/server/lib/nixstasis_web/controllers/`
- `packages/server/lib/nixstasis_web/live/`
- `docs/src/modules/edge-caddy.md`
- `docs/src/client-server-interface.md`
- Suggested validation:
- Add request/LiveView tests for allowed and denied role scenarios once the
  contract is implemented.
- Run `mdbook build docs` and ensure Architecture, Operations, and Reference
  pages all point to the final authorization contract.
- Suggested first workflow command: `/start-feature authcrunch-role-contract`

### Production operations runbooks (`production-operations-runbooks`)

- Status: completed
- Overview:
- Add production operations runbooks that go beyond the Compose deployment
  contract. Cover backup/restore, secret rotation, incident response,
  monitoring, upgrade checks, and explicit HA/non-HA expectations for the
  supported deployment shape.
- Requirements:
- Document PostgreSQL backup and restore workflows for bundled and external
  database modes.
- Document secret rotation procedures for Phoenix secrets, AuthCrunch/OIDC
  values, JWT key material, FRPS auth/dashboard credentials, and database
  credentials.
- Document operational health checks for Phoenix, Caddy, FRPS, PostgreSQL,
  device heartbeat freshness, E2E retention, and remote-access availability.
- Document incident-response playbooks for failed migrations, broken TLS
  approval, FRPS token exposure, device credential compromise, and E2E
  retention/log failures.
- Document upgrade and rollback validation steps for Compose services and client
  release artifacts.
- State HA/scaling boundaries clearly: what the supported Compose deployment
  does and does not guarantee.
- Constraints:
- Do not imply unsupported HA or clustered deployment semantics unless they are
  implemented and tested.
- Keep production runbooks separate from local development harness guidance.
- Preserve `deploy/compose` as the supported server deployment path.
- Non-goals:
- Building a hosted operations platform.
- Replacing operator-specific backup tooling.
- Implementing HA as part of the documentation feature.
- Success criteria:
- A production operator can restore service from backup using documented steps.
- A production operator can rotate each documented secret without guessing which
  services must restart.
- The docs identify observable symptoms, immediate mitigations, and validation
  checks for common incidents.
- HA and scaling expectations are explicit rather than implied.
- Risks and tradeoffs:
- Runbooks can become stale if they duplicate scripts without linking to source
  validation.
- Over-prescriptive backup tooling can conflict with an operator's managed
  database platform.
- Completion notes:
- Production operations runbooks are available under `docs/src/operations/` and
  cover backup/restore, secret rotation, health checks, incident response,
  upgrades/rollbacks, and HA/scaling expectations.
- The feature task list in
  `docs/src/features/production-operations-runbooks/tasks.md` is complete.
- Operations navigation is linked from `docs/src/SUMMARY.md`.
- Dependencies:
- `deploy/compose/docker-compose.yml`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `deploy/compose/README.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/runtime-boundaries.md`
- Suggested validation:
- Exercise backup/restore against a disposable Compose stack.
- Run runtime contract checks before and after documented secret rotation steps.
- Run `mdbook build docs` and verify Operations navigation points to the new
  runbooks.
- Suggested first workflow command: `/start-feature production-operations-runbooks`

### Rich API examples (`rich-api-examples`)

- Status: completed
- Overview:
- Add example-rich API documentation for maintained HTTP contracts. Provide
  representative requests and responses for successful calls, validation
  errors, authorization failures, conflict/locking behavior, and important
  edge cases across `/api/v1`, `/e2e`, builder APIs, and retained bespoke
  OpenAPI files.
- Requirements:
- Add examples for device registration, pending approval, approved credential
  issuance, heartbeat, command delivery, command results, deferred payload
  fetches, and Caddy `check_domain` decisions.
- Add examples for E2E run creation, idempotent reuse, environment lock
  conflicts, protocol mismatch, seed failures, result submission, cancellation,
  and missing/pruned logs.
- Add examples for builder schema option lookup, validation success, validation
  failure, stale selections, missing schemas, and authorization failures where
  applicable.
- Add examples for report APIs that remain hand-maintained and link alert-rule
  contracts to generated Ash OpenAPI.
- Keep OpenAPI examples and prose examples synchronized, or link one canonical
  source from the other.
- Constraints:
- Do not invent behavior that is not implemented or tested.
- Distinguish Ash-generated `/api/json` examples from bespoke `/api/v1` and
  `/e2e` controller examples.
- Keep secrets, real tokens, hostnames, and operator data out of examples.
- Non-goals:
- Replacing generated Ash OpenAPI.
- Changing API behavior.
- Creating exhaustive API tutorials for every LiveView browser route.
- Success criteria:
- API consumers can copy representative request/response shapes for each durable
  runtime contract.
- Error examples cover the common failure classes operators and client authors
  must handle.
- `mdbook build docs` succeeds and OpenAPI references remain linked from the
  Reference section.
- Risks and tradeoffs:
- Examples can drift unless they are derived from tests or reviewed when
  controllers change.
- Too many examples can obscure the canonical contract if not organized by API
  surface.
- Completion notes:
- Rich API examples are documented in `docs/src/client-server-interface.md` with
  traceable implementation, test, and OpenAPI references.
- Generated Ash contracts remain linked through
  `packages/server/priv/static/openapi.yaml`; bespoke controller contracts
  remain under `docs/src/reference/openapi/`.
- The feature task list in `docs/src/features/rich-api-examples/tasks.md` is
  complete.
- Dependencies:
- `docs/src/client-server-interface.md`
- `docs/src/reference/openapi/`
- `packages/server/priv/static/openapi.yaml`
- `packages/server/lib/nixstasis_web/controllers/`
- `packages/client/internal/transport/client.go`
- Suggested validation:
- Compare examples against controller tests and client transport tests.
- Run `mdbook build docs` and, where practical, OpenAPI validation for example
  payloads.
- Suggested first workflow command: `/start-feature rich-api-examples`

### Server stary script workbench (`server-stary-script-workbench`)

- Status: implemented
- Overview:
- Delivered a server web interface for creating, editing, validating, testing, and
  deploying Stary scripts. The UI should include a structured front-matter
  editor, a script body editor, syntax/schema validation, and a workflow for
  running candidate scripts on one or more selected clients before rollout.
- Requirements:
- Provide a script inventory in the server web UI with draft, validated, tested,
  deployed, failed, and archived states.
- Provide a front-matter model editor for script metadata, unique name, output
  schema, timeout or warning metadata when supported, and other fields required
  by the existing `stary` format.
- Provide a script body editor for the Starlark portion of the script.
- Validate YAML front matter, Stary file structure, declared output schema, and
  Starlark parseability before a script can be queued for testing or
  deployment.
- Reuse the existing client Stary semantics for runtime behavior; do not create a
  separate server dialect that can pass validation but fail on clients.
- Allow an operator to select one or more clients for test execution.
- Dispatch test runs through the existing authenticated client command path or a
  deliberately designed successor, and capture per-client status, output,
  warnings, validation errors, execution errors, and timeout results.
- Keep test runs separate from deployed polling scripts so operators can test a
  draft without affecting normal telemetry collection.
- Provide a deployment workflow that installs or updates a validated script on
  selected clients only after an explicit operator action.
- Record script versions, validation results, test results, deployment targets,
  actor identity, and timestamps for audit and rollback decisions.
- Surface deployment and test failures in the UI without blocking unrelated
  clients from reporting normal telemetry.
- Constraints:
- The client remains the authoritative execution boundary for Starlark builtins,
  command allowlisting, timeouts, and output validation.
- Server-side validation must not require shelling out to an unmanaged client
  binary in production unless that dependency is explicitly packaged and
  supervised.
- Script test commands must be authenticated, authorized, bounded by timeout, and
  rate limited so the web interface cannot become an unbounded remote execution
  surface.
- Draft scripts and test results may contain sensitive operator-authored logic or
  device output and must follow the same authorization model as other
  operator-only device controls.
- Deployment must preserve client-local safeguards: malformed scripts, schema
  mismatches, and forbidden builtins still fail on the client.
- Non-goals:
- Replacing client-local `test_script`, `repl`, `list_scripts`,
  `install_script`, or `remove_script` workflows.
- Building a collaborative IDE with real-time multi-user editing.
- Providing a full source-control system for scripts in the first increment.
- Automatically deploying scripts to every client without an explicit target
  selection.
- Designing a new scripting language or changing Stary file syntax.
- Success criteria:
- An operator can create or edit a draft Stary script in the server UI using a
  structured front-matter editor and Starlark body editor.
- Invalid front matter, invalid schema declarations, malformed Stary structure,
  and Starlark syntax errors are caught before the script can be tested.
- The operator can choose one or more connected clients, run the draft as a test,
  and inspect each client's output, warnings, validation status, execution
  status, and errors.
- Test execution does not install the draft as a normal polling script.
- The operator can deploy a validated and tested script to selected clients and
  see per-client deployment status.
- Scripts that call `exec_cmd` surface the client runtime's allowlist rejection
  clearly during test execution when the selected client has not enabled the
  requested command.
- Audit records identify who validated, tested, and deployed each script version,
  what clients were targeted, and what result each client reported.
- Existing client-side Stary CLI tests and runtime tests continue to pass.
- Risks and tradeoffs:
- A rich editor can grow into a large IDE feature; the first version should focus
  on structured front matter, basic code editing, validation, test dispatch, and
  deployment state.
- Server-side validation improves feedback speed but can become misleading if it
  does not use the same parser and validation rules as the Go client.
- Running tests on live clients provides fidelity but introduces remote execution
  risk, uneven client availability, and per-client builtin differences.
- Deploying scripts from the server centralizes operations but creates versioning,
  audit, rollback, and authorization requirements that client-local files did
  not have.
- Dependencies:
- `docs/src/features/starlark-script-system/design.md`
- `packages/client/internal/script/format.go`
- `packages/client/internal/script/runtime.go`
- `packages/client/internal/script/validator.go`
- `packages/client/cmd/nixstasis/test_script.go`
- `packages/client/cmd/nixstasis/install_script.go`
- `packages/client/internal/commands/handler.go`
- `packages/client/internal/transport/client.go`
- `packages/server/lib/nixstasis_web/live/`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex`
- `packages/server/lib/nixstasis/devices/`
- `packages/server/lib/nixstasis/domain.ex`
- Implementation status:
- Server persistence, LiveView inventory/detail screens, structured front-matter
  editing, body editing, validation, scoped test/deployment queueing, per-device
  action display, live refresh, retry, and cancel/mark-failed controls are
  implemented.
- Validation requires an explicit front-matter version, and test/deploy commands
  use immutable validated version content rather than the mutable draft body.
- Deferred `run_script` payloads are hydrated by the client poll loop before
  execution; missing payloads produce failed client results.
- Operator audit events carry trusted actor identity, device results remain device-
  attributed, and audit retention follows deployment structured logging rather
  than a new application table.
- Reader-facing documentation is delivered in the Server Scripts and Stary Script
  Workbench operations pages; browser smoke testing against a Compose device lab
  remains a separately recorded validation limitation when that lab is unavailable.
- Suggested validation:
- Server tests for script draft persistence, status transitions, authorization,
  and audit event creation.
- Parser/validation contract tests that prove server-side validation accepts and
  rejects the same Stary front matter and schemas as the Go client.
- LiveView tests for the front-matter editor, script body editor, validation
  errors, client selection, and test/deploy actions.
- Client command tests for test-only script execution and install/update
  commands, including timeout, forbidden builtin, invalid schema, and malformed
  script cases.
- End-to-end test that creates a draft in the UI, validates it, tests it on one
  or more clients, deploys it to selected clients, and observes the resulting
  telemetry/reporting behavior.
- End-to-end test that runs an `exec_cmd` script against a selected client and
  shows the client's allowlist rejection as a test result when the command is
  not enabled.
- Delivered documentation: [Stary Script Workbench operations](operations/script-workbench.md),
  [Server Scripts](modules/server-scripts.md), and the [implemented feature record](features/server-stary-script-workbench/index.md).

### Server command allowlist management (`server-command-allowlist-management`)

- Status: implemented
- Overview:
- Add a server web interface for defining `exec_cmd` command allowlists,
  grouping allowlists into reusable categories, and assigning the resulting
  command policy to selected devices. This gives operators a controlled way to
  grant Stary scripts the host-command capabilities they need without changing
  the client runtime's deny-by-default security boundary.
- Requirements:
- Provide a command allowlist inventory in the server web UI with name,
  description, status, version, command entries, and audit metadata.
- Each command entry must identify the operator-facing command name and the
  absolute executable path that the client should allow.
- Reject command entries with relative paths, shell fragments, empty names,
  ambiguous path aliases, or duplicate command names within the same resolved
  policy.
- Provide allowlist categories that group one or more allowlists into a larger
  additive policy, so operators can create reusable categories such as
  diagnostics, networking, service health, or hardware inspection.
- Allow categories to include other categories only if cycle detection and clear
  resolved-policy preview are implemented; otherwise keep first-version
  composition to direct allowlist membership.
- Provide assignment workflows for selecting which devices receive which
  allowlists or categories.
- Show the resolved command policy for each targeted device before deployment,
  including command name, absolute path, source allowlist or category, version,
  and any conflict that blocks deployment.
- Deliver assigned policy to clients through an authenticated device command,
  heartbeat payload extension, or another explicit device-runtime contract.
- Make clients persist the active command policy in a client-owned runtime config
  location and load it into `RuntimeConfig.ExecCommandAllowlist` before Stary
  scripts execute.
- Record policy versions, assigned devices, actor identity, timestamps, and
  client acknowledgement or failure results.
- Provide rollback or reassignment behavior so operators can remove a command
  grant from selected devices and observe acknowledgement.
- Constraints:
- `exec_cmd` remains deny-by-default when no policy is assigned or when policy
  delivery fails.
- The server must not allow operators to authorize arbitrary shell strings; only
  named commands resolving to absolute executable paths are in scope.
- Additive category composition must not hide conflicts. If two sources define
  the same command name with different absolute paths, deployment should fail
  until the operator resolves the conflict.
- Policy assignment must be authorized as an admin/operator capability, not a
  viewer capability.
- Client-side enforcement remains mandatory; server policy validation is not a
  substitute for the client checking the allowlist at execution time.
- Policy delivery must be idempotent and safe across missed heartbeats, duplicate
  command IDs, offline devices, and downgraded clients that do not support
  remote allowlist updates.
- Non-goals:
- Implementing arbitrary argument allowlisting in the first increment unless the
  script runtime already enforces argument-level policy.
- Granting direct interactive shell access.
- Automatically inferring required commands by parsing Stary script bodies.
- Replacing OS-level permissions, sudo policy, or service-account hardening.
- Building per-script sandboxing beyond the existing Stary runtime boundary.
- Success criteria:
- An operator can create small command allowlists with explicit command names and
  absolute executable paths.
- An operator can group allowlists into larger categories and preview the
  resolved additive policy.
- An operator can assign an allowlist or category to one or more devices and see
  per-device pending, acknowledged, failed, and active policy status.
- A client with no assigned allowlist rejects `exec_cmd`.
- A client with an assigned allowlist accepts only the configured command names
  or exact absolute paths and rejects unlisted commands.
- Removing or changing an assignment eventually updates the client's active
  policy and is visible in the server UI.
- Audit records identify who created, changed, assigned, removed, and deployed
  each allowlist policy version.
- Risks and tradeoffs:
- Command allowlists are powerful device-control policy. Weak authorization,
  vague paths, or hidden category inheritance would turn a script feature into
  a broad remote execution surface.
- Additive categories are simpler and easier to reason about than allow/deny
  precedence, but they require explicit cleanup when an operator wants to
  narrow permissions.
- Absolute paths are safer than PATH lookup, but operators must account for
  distro differences across device fleets.
- Client acknowledgement may lag because offline devices only receive policy on
  a later poll cycle.
- Dependencies:
- `packages/client/internal/script/builtins_exec.go`
- `packages/client/internal/script/runtime.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/internal/commands/handler.go`
- `packages/client/internal/transport/client.go`
- `packages/server/lib/nixstasis/devices.ex`
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex`
- `packages/server/lib/nixstasis_web/live/`
- `packages/server/lib/nixstasis/domain.ex`
- `docs/src/modules/client-starlark-runtime.md`
- `docs/src/data-flow.md`
- Suggested validation:
- Server tests for allowlist/category CRUD, conflict detection, cycle detection
  if nested categories are supported, device assignment, authorization, audit
  events, and policy versioning.
- LiveView tests for creating allowlists, composing categories, previewing a
  resolved device policy, assigning to devices, and removing assignments.
- Client tests proving `RuntimeConfig.ExecCommandAllowlist` is populated from the
  delivered policy and that `exec_cmd` rejects unassigned, relative, mismatched,
  and conflicting command entries.
- Command-delivery or heartbeat-contract tests covering offline devices,
  duplicate deliveries, unsupported clients, acknowledgements, and rollback.
- End-to-end test that assigns a diagnostics allowlist to a test device, runs a
  Stary script using an allowed command, then removes the assignment and proves
  the same script can no longer execute the command.
- Suggested first workflow command: `/start-feature server-command-allowlist-management`

### Dashboard device groups (`dashboard-device-groups`)

- Status: completed
- Beads root: `nixstasis-vpu`
- Design: [Dashboard Device Groups](features/dashboard-device-groups/design.md)
- Delivered record: [Dashboard Device Groups](features/dashboard-device-groups/index.md)
- Sequencing: persistence precedes scoped reads and metadata orchestration, membership writes, audit/refresh integration,
  metadata UI, membership UI, route filtering, and documentation.
- Overview:
- Add operator-managed device groups to the Dashboard Devices view. Operators can
  create groups, edit group metadata, assign and remove devices, and filter the
  device list by group.
- Requirements:
- Provide a groups management surface from the Devices view, including create,
  rename, describe, archive/delete, and membership count behavior.
- Support assigning one or more selected devices to a group from the existing
  Devices table selection workflow.
- Support removing one or more selected devices from a group without deleting the
  device records.
- Allow a device to belong to multiple groups.
- Add group filters to the Devices list and preserve them in route-backed filter
  state alongside existing product, account number, IPv4, approval status,
  connectivity status, search, and sort parameters.
- Show group membership in the Devices list or detail flow without making the
  table unreadable on small screens.
- Provide empty, loading, unauthorized, and conflict states for group management.
- Keep group membership updates auditable with actor identity, timestamp, device
  IDs, group ID, and action.
- Expose a domain/context API for group CRUD, membership assignment, membership
  removal, device listing by group, and group membership lookup.
- Constraints:
- Device groups are manual operator organization, not automatic product-name or
  account-number grouping.
- Group membership must not change device registration, approval, heartbeat,
  remote-access, or API-token behavior.
- Group management requires device management permission; read-only users may
  filter or view groups only if their device permissions allow those devices.
- Existing scoped-device authorization must still apply when listing group
  members or applying group filters.
- Deleting or archiving a group must not delete devices.
- Non-goals:
- Rule-based dynamic groups in the first increment.
- Nested groups or hierarchy.
- Per-group RBAC inheritance.
- Bulk device import/export.
- Replacing existing product, account, status, or search filters.
- Success criteria:
- An authorized operator can create a device group from the Devices view.
- An authorized operator can select devices in the table and add them to or
  remove them from a group.
- A device can appear in multiple groups and group membership is visible from the
  Devices workflow.
- Filtering the Devices list by group returns the expected devices and composes
  correctly with existing filters and search.
- Unauthorized users cannot manage groups or infer devices outside their allowed
  device scope through group membership.
- Group create, update, membership add/remove, and archive/delete actions are
  covered by audit events or an equivalent traceable history.
- Risks and tradeoffs:
- Manual groups are straightforward and predictable, but operators must maintain
  membership as fleets change.
- Showing group membership in a dense device table can add clutter; the UI should
  use compact summaries and defer detailed editing to a focused panel or modal.
- Many-to-many group membership requires careful filtering and scoped
  authorization tests to avoid leaking device existence.
- Dependencies:
- `packages/server/lib/nixstasis/devices.ex`
- `packages/server/lib/nixstasis/devices/device.ex`
- `packages/server/lib/nixstasis_web/live/device_live/index.ex`
- `packages/server/lib/nixstasis_web/live/device_live/index.html.heex`
- `packages/server/lib/nixstasis_web/permissions.ex`
- `packages/server/lib/nixstasis/domain.ex`
- `docs/src/features/device-detail-page/design.md`
- `docs/src/features/dashboard-home/design.md`
- Suggested validation:
- Server/domain tests for group CRUD, uniqueness rules, membership add/remove,
  multi-group membership, delete/archive behavior, and device filtering by
  group.
- LiveView tests for creating groups, adding selected devices, removing selected
  devices, filtering by group, preserving query params, and unauthorized states.
- Authorization tests proving scoped users only see allowed group memberships and
  cannot manage groups without device-management permission.
- Regression tests proving existing product, account, IPv4, approval,
  connectivity, search, and sort filters continue to compose correctly.
- `mix ash.codegen --check` if Ash resources or relationships change.
- Delivery evidence is recorded in the implemented-feature record and Beads lifecycle.

### Server curated command package catalog (`server-curated-command-package-catalog`)

- Status: completed
- Beads root: `nixstasis-o4t`
- Design: [Server Curated Command Package Catalog](features/server-curated-command-package-catalog/design.md)
- Delivered record: [Server Curated Command Package Catalog](features/server-curated-command-package-catalog/index.md)
- Sequencing: client inventory and server catalog resolver precede catalog-backed policy UI and delivery; end-to-end validation follows the UI and delivery integration.
- Overview:
- Add a server-curated package and command catalog for command policy authoring.
  Operators choose approved package-backed commands from the server catalog
  instead of manually typing absolute executable paths. Device-reported
  inventory is evidence only; the catalog remains the policy authority.
- Requirements:
- During heartbeat, clients report `/etc/os-release`, architecture, detected
  package manager, and enough package/command inventory to verify catalog
  compatibility.
- Keep the server catalog as the source of truth for package names, supported OS
  families, command names, descriptions, categories, and risk/installation
  guidance.
- Let operators create command policies from catalog commands or catalog
  categories without manually entering absolute paths.
- Resolve the final executable path per device before enforcement, then continue
  delivering exact absolute-path allowlists to clients.
- Show compatibility status per target device: supported, package installed,
  command path resolved, stale inventory, missing package, unsupported OS, or
  conflict.
- Treat device-discovered commands and paths as untrusted verification data, not
  as automatic allowlist authority.
- Keep package installation as an explicit operator-approved action if added;
  policy assignment must not silently install software.
- Constraints:
- The existing client runtime must remain deny-by-default.
- The final execution boundary remains command-name to absolute-path allowlists;
  package catalog entries are an authoring and resolution layer, not a looser
  runtime permission model.
- Catalog package mappings must be OS-aware, with separate names or unsupported
  states for Debian/Ubuntu, Fedora/RHEL, NixOS, and other distributions.
- Clients must not be able to expand their own permissions by advertising extra
  commands, alternate paths, or package names.
- Non-goals:
- Arbitrary package search/install from public repositories in the first
  increment.
- Silent or automatic package installation during policy assignment.
- Argument allowlisting or shell-fragment policies.
- Trusting discovered commands as server-approved policy entries.
- Success criteria:
- An operator can select a catalog-backed command such as `df` without knowing
  `/usr/bin/df`.
- The server shows whether selected devices support the catalog entry before
  assignment.
- A client receives and enforces the same absolute-path policy shape used by the
  existing command allowlist system.
- A compromised or incorrect client inventory report cannot create new approved
  catalog commands by itself.
- Risks and tradeoffs:
- A curated catalog is safer than discovered-command authoring, but it requires
  maintenance as package names and distro behavior change.
- Per-device path resolution improves usability, but the server must make stale
  or missing inventory obvious before assignment.
- Package installation support crosses a stronger trust boundary than command
  allowlisting and should be separately approved, audited, and reversible.
- Dependencies:
- `docs/src/features/server-command-allowlist-management/design.md`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/internal/commands/handler.go`
- `packages/server/lib/nixstasis/command_allowlists.ex`
- `packages/server/lib/nixstasis_web/live/command_policy_live/index.ex`
- `packages/server/lib/nixstasis/devices/device.ex`
- Suggested validation:
- Client tests for OS-release parsing, package-manager detection, and command
  path resolution reporting.
- Server tests proving catalog entries, OS mappings, compatibility checks, and
  resolved absolute-path policy delivery.
- LiveView tests for catalog command selection, missing-package warnings,
  unsupported-device states, and conflict handling.
- Security tests proving untrusted device inventory cannot authorize commands not
  present in the server catalog.
- Suggested first workflow command: delivered; see the implemented-feature record for audit and validation evidence.

## Migrated Legacy Feature History

These entries preserve completed and active feature identities that were present in legacy feature records but omitted
from the current roadmap narrative.

### Add rule modal improvements (`add-rule-modal-improvements`)

- Status: implemented; measured success criteria deferred
- Overview: Improve Add Rule validation, keyboard and accessibility behavior, dirty-close recovery, and first-attempt save usability without changing alert-rule semantics.
- Beads root: `nixstasis-inh`
- Design: [Add Rule Modal Improvements](features/add-rule-modal-improvements/design.md)
- Delivered record: [Add Rule Modal Improvements](features/add-rule-modal-improvements/index.md)
- Completion notes: The `/alerts` Add/Edit Rule modal now has accessible dialog/error associations, contained focus including nested discard confirmation, keyboard save behavior, preserved validation feedback, and per-LiveView duplicate-submit protection. SC-001, SC-002, and SC-004 measurements remain deferred because no defensible baseline or controlled observation window exists; no metric pass/fail is claimed. Legacy `/alerts/rules` consolidation remains outside scope.

### Dashboard home (`dashboard-home`)

- Status: completed
- Overview: Deliver the operational dashboard home and its monitoring summaries.

### Device detail page (`device-detail-page`)

- Status: completed
- Overview: Deliver device detail navigation, telemetry, controls, and remote-session workflows.

### Go client rewrite (`go-client-rewrite`)

- Status: completed
- Overview: Deliver the supported Go device agent, runtime, packaging, and client/server protocol implementation.

### Iot device monitoring (`iot-device-monitoring`)

- Status: completed
- Overview: Deliver device registration, approval, heartbeat, telemetry, alerting, and monitoring workflows.

### Packaging deployment migration (`packaging-deployment-migration`)

- Status: completed
- Overview: Establish the supported Compose server deployment and GoReleaser client release paths.

### Phoenix UI polish (`phoenix-ui-polish`)

- Status: completed
- Overview: Deliver the Phoenix and LiveView interaction, layout, and visual quality improvements.

### Report view improvements (`report-view-improvements`)

- Status: completed
- Overview: Deliver report filtering, sorting, result browsing, saved view preferences, and deletion workflows.

### Schema driven builder dropdowns (`schema-driven-builder-dropdowns`)

- Status: in-progress
- Overview: Deliver schema-backed builder options while retaining outstanding performance and close-out validation.

### Server client e2e tests (`server-client-e2e-tests`)

- Status: completed
- Overview: Deliver the client-driven E2E harness, server lifecycle APIs, reporting, retention, and CI publication.

### Starlark script system (`starlark-script-system`)

- Status: completed
- Overview: Deliver the Stary/Starlark telemetry runtime, validation, builtins, CLI workflows, and execution safeguards.
