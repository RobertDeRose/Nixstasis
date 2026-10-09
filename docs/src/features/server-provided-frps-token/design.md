# Design — Server-Provided FRPS Token

## Authority and Scope

- Feature slug: `server-provided-frps-token`
- Feature root: `nixstasis-5hx`
- Current lifecycle correction: `nixstasis-n01`, PR #3 review item 9
- Delivery history: [index.md](index.md)

This is the current intended contract for the unreleased application. The legacy
shared-token design has been replaced by signed device/lease credentials and an
internal FRPS authorization plugin. The user approved redesigning lease identity,
ownership, recovery, and credential binding rather than patching an in-memory map.

## Goals

- Keep device runtime API tokens separate from FRPS credentials.
- Persist each remote-access lease independently, with stable identity and owner.
- Preserve bounded restart continuity and selective revocation.
- Prevent a credential from borrowing another lease's authorization.
- Keep route definitions and local targets exclusively client-owned.
- Avoid restarting FRPC for every freshly signed heartbeat.

## Non-Goals

- Redesigning browser or terminal authentication.
- Supplying arbitrary FRPC configuration, targets, or headers from Phoenix.
- Immediately disconnecting established FRPS tunnels through a new control API.
- Retaining compatibility with unowned device-summary authorization or old tokens.

## Durable Authority

`RemoteAccessLease` is an internal-only Ash/PostgreSQL resource. It has no public
JSON API routes or resource actions. Each row stores:

- stable lease UUID and device UUID;
- owner kind (`session`, `direct`, or `provisioning`) and owner UUID;
- trusted audit subject, when available;
- immutable profile and absolute UTC expiry;
- creation/update timestamps and explicit revocation timestamp.

Session/direct owners use a unique lease-scoped owner UUID. Provisioning uses the
persisted delivery UUID. A unique owner key prevents a resumed delivery from
creating another lease or renewing its original expiry. Provisioning ownership
also requires the matching device's delivery to remain nonterminal and not
withdrawn; recording completion immediately invalidates its credential even if
lease cleanup is interrupted.

Device requested/profile/expiry/owner fields are a projection, not authorization
sources. Writing a device attribute cannot grant or revoke access. Authorized
profile updates save a separate preferred profile for future operator leases;
they do not mutate an existing lease's profile. Explicit device-wide withdrawal
through `Devices.set_remote_access(device, false)` revokes every lease. Delivery
and browser cleanup instead close their own stable lease UUID.

Unrelated heartbeat/metadata updates must not write lease projections from an
earlier changeset snapshot. Their responses refresh current stored summary fields
after the update. Profile preference changes reconcile the selected lease under
the same device-row lock and transaction; failure rolls back both preference and
projection.

## Overlap and Profile Selection

A client runs one FRPC profile at a time:

1. A live provisioning lease takes precedence over session/direct leases, so a
   new browser cannot interrupt an upload.
2. Within either class, the newest creation timestamp wins; UUID breaks ties.
3. The selected lease supplies both profile and expiry. Never combine one lease's
   profile with another lease's longer lifetime.
4. Closing or expiring the selected lease restores the next eligible lease and
   its own profile/expiry. Other owners' leases are not revoked.
5. Only the selected lease's credential may authorize new FRPS operations.

The device row is locked while lease creation/revocation and projection updates
commit in one database transaction. Timers and PID monitors are acceleration and
notification mechanisms, not authority. Session owners are monitored while
attached; PIDs are never persisted or reconstructed. After restart, durable
identities remain valid until explicit revocation or their original expiry.
Provisioning expiry notifications route to the registered provisioning worker,
not to a stale PID.

## Recovery

The lease manager restores the original live rows and UUIDs, not a synthetic
lease reconstructed from device flags. Expired, revoked, orphaned, terminal, or
withdrawn provisioning authorizations cannot be restored. Device projections
are rebuilt from eligible leases; missing ownership fails closed.

Provisioning resolves its lease through the durable delivery owner key for
withdrawal, polling, resume, and completion. An empty worker map is harmless.
Resume never uploads again, creates a replacement lease, or extends the original
expiry. Missing/expired authorization requires explicit operator reconciliation.

The named migration must run before starting the new server. Old device-summary
flags are not converted into invented leases, and old signed credentials are
rejected. Inactive configured profiles are preserved. Existing development
sessions must be reopened explicitly after this migration.

## Heartbeat and Credential Contract

Authenticated heartbeats with an eligible selected lease carry:

- `remote_access_token`: signed device identity, lease UUID, profile, and expiry;
- `remote_access_lease_id`: selected lease UUID;
- `remote_access_expires_at_ms`: Unix-millisecond credential expiry;
- `remote_access_profile`: client-owned name and version (`1`).

Credential expiry is bounded by the selected lease and signing maximum age.
`FrpsToken.verify/1` checks signature, expiry, current selected lease identity,
profile, and stored expiry. Login additionally checks the device user; NewProxy
removes only that verified user prefix and enforces device-owned route names and
domains. Deletion, revocation, expiry, or selection of another lease rejects the
credential even if another authorization remains active for the device.

The client tracks the lease actually installed in FRPC. A lease identity or
profile change triggers one bounded restart even if expiry increases. Within the
same lease, shortened validity or renewal near expiry refreshes the credential;
a changed signature alone does not. Missing/expired credentials stop FRPC.
Credentials are supplied through a root-only session environment file and FRPS
plugin metadata, never through a deployment-wide client secret.

Revocation blocks new Login/NewProxy operations immediately after commit. Existing
tunnels are stopped through the next authenticated heartbeat; this design does
not claim instantaneous teardown of established FRPS connections.

## Documentation Impact

- `deploy/compose/README.md`
- `docs/src/operations/secret-rotation.md`
- `docs/src/planned-features.md`
- `docs/src/client-server-interface.md`
- `docs/src/data-flow.md`
- `docs/src/modules/server-devices.md`
- `docs/src/modules/server-provisioning.md`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/client-transport.md`
- `docs/src/modules/edge-frp.md`
- `docs/src/reference/openapi/device-api.yaml`
- `docs/src/features/atomixos-bootstrap-provisioning/design.md`
- Both affected feature delivery records

## Validation

Behavioral tests must cover stable identity after restart, independent overlapping
leases, profile/expiry selection and restoration, provisioning precedence,
withdrawal and resume after restart, no silent renewal, terminal-owner
invalidation, credential isolation, expired/deleted authorization, ignored device
flags, immutable lease profiles, and transaction rollback for invalid ownership.
Stage device updates across concurrent lease open/close operations to verify that
neither persisted nor returned projections become stale; preference reconciliation
must roll back with its parent update.
Client tests must distinguish lease replacement from signature-only rotation.

Generate named Ash migrations/snapshots, verify `mix ash.codegen --check`, regenerate
OpenAPI, run focused server/client tests and repository checks, and obtain an
isolated quality/security/maintainability review before committing. Beads retains
validation evidence; feature delivery records reconcile the accepted design.
