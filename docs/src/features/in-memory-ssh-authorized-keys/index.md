# In-Memory SSH Authorized Keys

## Delivery Summary

- Beads feature root: `nixstasis-bdv`
- Status: implemented and reconciled; delivery action pending
- Pull request: not created; no PR action selected
- Merge commit: not merged; fast-forward delivery remains available
- Design record: [design.md](design.md)

## Delivered Capability

Browser-terminal SSH authorization now uses OpenSSH `AuthorizedKeysCommand` and
an in-memory, TTL-bound authorization store in the Go client. The server queues
versioned `ssh_authorize` and `ssh_revoke` commands, targets the dedicated
`nixstasis-support` account, and exposes the terminal socket only after the
matching authorization result is acknowledged.

The installed helper and client use the fixed local socket
`/run/nixstasis/ssh-authority.sock`. Native packages and the Compose image
provision separate `nixstasis`, `nixstasis-support`, and locked
`nixstasis-ssh-authority` identities. Browser-terminal keys are not written to
persistent `authorized_keys` files.

## User-Facing Behavior

- A terminal session authenticates as `nixstasis-support` through the existing
  FRP/OpenSSH path.
- The browser terminal does not receive a socket token until the matching
  dynamic `ssh_authorize` command returns `OK`.
- Positive, bounded TTLs, matching session refs, canonical public-key material,
  and the exact versioned content types are required.
- Unknown, expired, revoked, malformed, wrong-user, unavailable, and mismatched
  keys fail closed without printing an authorized key.
- Terminal close, failed joins, authorization timeout, offline transitions, SSH
  startup failure, and lease expiry clear server key material first and queue a
  bounded, idempotent revoke when possible.
- Client restart empties the in-memory store and invalidates browser-terminal
  authorizations.

## Design Integration

Phoenix remains authoritative for operator authorization, terminal session
lifecycle, and server-side private-key material. The Go client is authoritative
for device-local key validation, TTL expiry, revocation, and IPC responses.
OpenSSH enforces login for `nixstasis-support`; the helper is only an adapter and
FRP remains transport. No capability negotiation, TCP IPC, persistent-key
fallback, or broader helper privilege was introduced.

## Operational Impact

Installers and the Compose client provision the support account, locked helper
identity, socket group, runtime directory, root-owned helper, and OpenSSH
configuration. The helper and client must be available for support SSH login;
missing client or IPC state denies authentication rather than falling back to a
file. The supported IPC path is fixed at
`/run/nixstasis/ssh-authority.sock`; non-default runtime socket settings are
ignored with a warning. In the nested-systemd Compose client, an unprivileged
poll service falls back to a poll-owned, one-hour-bounded FRP session when the
system manager denies `systemd-run`; native root-managed installations retain
the transient systemd unit path.

The host real-sshd integration is focused Linux coverage. The separate
Compose/browser smoke remains deferred until a configured lab provides runtime
secrets, authenticated Caddy/OIDC, a managed device, and browser automation.

## Reference and Contracts

- [API & Runtime Contracts](../../reference/contracts.md#browser-terminal-ssh-authorization-contract)
- [Client-Server Interface](../../client-server-interface.md)
- [Data Flow](../../data-flow.md)
- [Runtime Boundaries](../../runtime-boundaries.md)
- [Server Devices](../../modules/server-devices.md)
- [Client Command Handler](../../modules/client-command-handler.md)
- [Client FRP Manager](../../modules/client-frp-manager.md)
- [Client Transport](../../modules/client-transport.md)
- [Deployment Compose](../../modules/deployment-compose.md)
- [OpenAPI Contracts](../../reference/openapi/device-api.yaml)
- Client installation and packaging: `packages/client/README.md`
- Compose deployment details: `deploy/compose/README.md`

## Validation Evidence

Passed for the implementation commits:

- Server `mix precommit`: 593 tests, 0 failures, including the terminal-revoke
  migration regression test.
- Compose/browser smoke: `mise run deploy:dev -- up --clients 3` completed after
  rebuilding the feature images; browser terminal login returned
  `nixstasis-support`, `whoami` returned the support identity, navigation away
  closed the session, and the client acknowledged the revoke. The revoked
  public key was then submitted to the installed helper and produced empty
  output (denied).

Additional implementation evidence:

- Focused server authorization, device, channel, LiveView, and cleanup tests:
  114 and 27 tests, 0 failures respectively.
- Client `GOEXPERIMENT=jsonv2 go test ./...`: passed; Linux real-sshd coverage is
  skipped on macOS.
- `golangci-lint`: 0 issues; native packaging, GoReleaser snapshot/installer,
  Compose runtime-contract, shell syntax, and `node --check` checks passed.
- `uv run scripts/check-docs.py`: 0 errors and 16 existing legacy warnings.
- `mdbook build docs`, targeted Rumdl, YAML parsing, and `git diff --check` passed.

Known validation limitation:

- Repository-wide `mise run check` remains non-clean from pre-existing Markdown,
  typo, and cold-dependency debt outside this feature. The exact output is
  retained at `/tmp/nixstasis-bdv-close-mise-check-final.log`; scoped feature
  checks and the Compose/browser smoke passed.

## Design Reconciliation

### Delivered as Designed

- Dynamic in-memory authorization is the only browser-terminal key path.
- The server uses exact versioned `ssh_authorize` and `ssh_revoke` contracts,
  top-level `public_key`, matching session refs, bounded TTLs, and the
  `nixstasis-support` target.
- Terminal activation is gated on the matching acknowledged command, and all
  specified cleanup boundaries clear server key material before best-effort
  revoke.
- The client/helper IPC boundary is local-only, bounded, fail-closed, and fixed
  at `/run/nixstasis/ssh-authority.sock`.
- Native installers and the container preserve separate service, support, and
  locked helper identities without deleting operator-owned key files.

### Intentional Changes

- The implementation selected one fixed trusted socket path instead of allowing
  a configurable runtime path, preventing poll/helper drift and untrusted path
  selection.
- Host real-sshd integration and Compose/browser smoke are recorded as separate
  evidence classes; the former does not claim the latter.
- Nested-systemd Compose clients use a bounded poll-owned FRP session when the
  unprivileged poll service cannot create a system transient unit; native
  root-managed systemd remains the primary lifecycle path.
- The terminal-revoke migration now removes older duplicate revoke rows before
  creating its uniqueness constraint, preserving unrelated command rows.
- The reader-facing command contract is maintained in reference/OpenAPI docs,
  while the design remains planning authority.

### Deferred Work

- No feature-scope behavior is deferred. Repository-wide validation still has
  unrelated baseline Markdown, formatter, typo, and dependency debt.

### Rejected or Removed Scope

- Persistent browser-terminal `authorized_keys` files.
- File-based fallback, capability negotiation, TCP IPC, password login, or a
  privileged/general-purpose helper command path.
- Replacing FRP or changing the Phoenix/Caddy operator authorization boundary.

## Documentation Updated

- `docs/src/features/in-memory-ssh-authorized-keys/design.md`
- `docs/src/features/in-memory-ssh-authorized-keys/index.md`
- `docs/src/SUMMARY.md`
- `docs/src/features/index.md`
- `docs/src/planned-features.md`
- `docs/src/client-server-interface.md`
- `docs/src/data-flow.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/modules/client-command-handler.md`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/deployment-compose.md`
- `docs/src/modules/server-devices.md`
- `docs/src/reference/contracts.md`
- `docs/src/reference/openapi/device-api.yaml`
- `docs/src/reference/openapi/index.md`
- `packages/client/README.md`
- `deploy/compose/README.md`
- `packages/client/internal/frp/manager.go`
- `packages/server/priv/repo/migrations/20260803120000_deduplicate_terminal_revokes.exs`

## Audit Trail

- `1c6878d1` — reconciled the reviewed design and implementation graph.
- `4ea40f08` — completed native SSH authority packaging.
- `2919b569` — enforced dynamic SSH payload, key, TTL, and helper invariants.
- `e44dd5e8` — made terminal cleanup exception-safe and revocation idempotent.
- `77077e40` — bound terminal access to acknowledged authorization.
- `e5cb5435` — unified the trusted client/helper IPC socket path.
- `094ec8d7` — reconciled reader-facing SSH contracts and OpenAPI documentation.
- `6f53da39` — created the standalone implementation record and navigation.
- `0b258fc` — made terminal-revoke migration cleanup safe for existing data.
- `79f5373` — added the unprivileged nested-systemd FRP fallback.
- `faf002c` — recorded final Compose/browser smoke evidence.

Implementation children `.7.74-.7.80` and validation children `.7.65-.7.71`
are recorded in Beads; `.7.80.1` records the acceptance fixes. Close-out
review and delivery state remain tracked by `nixstasis-bdv.10-.12`.
