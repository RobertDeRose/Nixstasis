# Planned Features

## Project Overview

Nixstasis needs a Compose development harness that exercises the same remote-access
boundaries operators rely on in deployment. Local development must be able to test
dynamic TLS approval and browser-driven SSH terminal flows without waiting for a
production-like environment.

## Goals

- Provide a repeatable Compose development harness for end-to-end remote-access
  validation.
- Make Caddy on-demand TLS approval testable from local development workflows.
- Make UI-launched SSH terminal sessions testable from local development workflows.
- Keep the development workflow aligned with documented runtime boundaries for
  Phoenix, Caddy, FRPS, FRPC, and managed-device identity.
- Support an optional public-fidelity mode using DuckDNS or a real operator-owned
  domain when developers need to validate public ACME behavior.

## Non-Goals

- Replacing the supported production Compose deployment path.
- Changing production TLS policy or public ingress requirements.
- Building a full hosted staging environment.
- Making local development depend on public DNS or public certificate issuance when
  a local equivalent can validate the same application behavior.
- Requiring ngrok, localtunnel, or another third-party tunnel provider for the
  default development workflow.

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

- Document `exec_cmd` intent as deny-by-default and allowlist-gated by absolute
  executable path.
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

### `compose-dev-harness`

- Status: delivered
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

### `self-extracting-installer`

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
- `packages/client/scripts/fetch_frpc.sh`
- `.github/workflows/release_client.yml`
- `packages/client/scripts/release/verify_artifacts.sh`
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

### `server-provided-frps-token`

- Status: implemented
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

### `ash-api-contract-unification`

- Status: partially implemented
- Overview:
- Rework the custom Phoenix controller APIs that represent durable product
    contracts so they are exposed through Ash actions/resources where practical,
    allowing OpenAPI generation to become the source of truth for those APIs.
    Keep explicitly workflow-only endpoints as Phoenix controllers only when Ash
    would make the contract less clear.
- Requirements:
- Inventory every bespoke route under `/api/v1` and `/e2e` and classify it as
    resource/action-oriented or workflow-only.
- Move resource/action-oriented device, builder, and E2E APIs to Ash-backed
    actions/resources or Ash JSON:API routes where the behavior maps cleanly.
- Preserve current wire contracts for the Go client, Caddy `check_domain`, and
    E2E harness unless a deliberate versioned contract change is documented.
- Generate OpenAPI docs for the migrated Ash-backed APIs and remove duplicate
    hand-maintained OpenAPI sections when the generated docs cover them fully.
- Keep any remaining hand-written Phoenix controller contracts under
    `docs/src/reference/openapi/` with an explicit reason why they are not
    Ash-generated.
- Constraints:
- Do not break existing Go client registration, heartbeat, command result, or
    command payload behavior without a versioned migration plan.
- Do not force terminal, Caddy TLS approval, or E2E workflow endpoints into Ash
    if a controller boundary is clearer or safer.
- Maintain authentication and authorization semantics for device API keys,
    Caddy/AuthCrunch, and E2E enablement gates.
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
- Device runtime, report preview, Caddy TLS ask, E2E workflow, and laptop
    diagnostics remain bespoke controller routes with retained/deferred rationale
    in the reference docs.
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
- `packages/server/priv/static/openapi.yaml`
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

### `authcrunch-role-contract`

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

### `production-operations-runbooks`

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

### `rich-api-examples`

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
- Add examples for report and alert-rule API surfaces that remain hand-maintained
    outside generated Ash OpenAPI.
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
