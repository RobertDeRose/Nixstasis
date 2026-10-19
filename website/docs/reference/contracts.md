# API & Runtime Contracts

The exact formats and rules Nixstasis components rely on when they talk to each other. The table below shows where to
find each one. The command and authorization contracts that span several components are on this page.

## Where each contract lives

| Contract                                                  | Page                                                     |
|-----------------------------------------------------------|----------------------------------------------------------|
| Request and response schemas                              | [OpenAPI Contracts](openapi/index.md)                    |
| HTTP protocol behavior, rate limits, errors, and examples | [Client-Server Interface](../client-server-interface.md) |
| Device, heartbeat, command, and E2E sequences             | [Data Flow](../data-flow.md)                             |
| Trust boundaries                                          | [Runtime Boundaries](../runtime-boundaries.md)           |
| Deployment configuration                                  | [Deployment Configuration](deployment-configuration.md)  |
| What each module is responsible for, and its rules        | [Module Reference](../modules/index.md)                  |

## Command Policy Contract

`apply_command_policy` is delivered in heartbeat `commands` using payload content type `application/vnd.nixstasis.command-policy+json;version=1`.

Payload shape:

```json
{
  "assignment_id": "uuid",
  "version": "policy-123",
  "revision": 123,
  "commands": {
    "name": "/absolute/path"
  }
}
```

The client saves each accepted policy to disk, outside the scripts directory. Once a server policy is saved, it
replaces the local `runtime.exec_commands`; until then, the local config applies. An empty `commands` object is valid,
and allows nothing.

## Command Catalog Resolver Contract

The command catalog makes policies easier to write, but changes nothing on the device: a catalog-backed assignment still
becomes the absolute-path `apply_command_policy` payload above.

The catalog stores:

- approved catalog commands with command name, display name, category slugs, risk notes, install guidance, and active version;
- OS-family package mappings for `debian`, `fedora`, and `nixos`, each with package manager, package name, expected executable path, and install hint;
- the latest device command inventory snapshot with schema version, probe catalog version, observation time, architecture, OS release fields, package manager, package evidence, and command path evidence.

`Nixstasis.Domain.command_inventory_probe_manifest/0` returns the current probe catalog version (`catalog-v1`), and the
package names and command probes to ask devices about. Clients use it to limit what they report; it never authorizes
anything.

`Nixstasis.Domain.preview_catalog_command_compatibility/1` takes the selected `device_ids` and `catalog_command_ids`,
and returns whether each command can be resolved on each device:

| Status                  | Meaning                                                                                                                    |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|
| `stale_inventory`       | No matching inventory exists, its probe catalog version is not current, or its observation is older than `offline_window`. |
| `unsupported_os`        | The catalog has no supported mapping for the device OS family.                                                             |
| `supported`             | The catalog has a supported OS mapping, but inventory did not include package evidence for the mapped package.             |
| `missing_package`       | The catalog mapping exists, but inventory explicitly reports the mapped package as not installed.                          |
| `conflict`              | Inventory reports the catalog command at a different executable path than the server mapping expects.                      |
| `package_installed`     | The mapped package is installed, but the command path has not been resolved by inventory evidence.                         |
| `command_path_resolved` | The mapped package is installed and the observed command path matches the server mapping.                                  |

Only `command_path_resolved` lets an assignment go ahead without anything more from the operator. Packages, commands,
or paths that a device reports but the catalog has not approved are shown for diagnosis only, and can never become part
of a policy.

## Browser Terminal SSH Authorization Contract

Two separate checks protect a browser terminal. Caddy, AuthCrunch, and Phoenix decide whether the operator may open
one. The device's client and OpenSSH decide whether the one-off session key is accepted.

The server only ever sends the two commands below. There is no `authorized_keys_path`, no capability flag, and no
fallback to writing keys to a file.

### `ssh_authorize`

`ssh_authorize` is delivered in the device heartbeat `commands` array:

```json
{
  "command_id": "<uuid>",
  "type": "ssh_authorize",
  "public_key": "ssh-ed25519 AAAA... nixstasis-remote-access",
  "payload": {
    "content_type": "application/vnd.nixstasis.ssh-authorize+json;version=1",
    "name": "<session-ref>",
    "data": "{\"target_user\":\"nixstasis-support\",\"ttl_seconds\":300,\"session_ref\":\"<session-ref>\"}"
  }
}
```

- `public_key` sits at the top level, and is the full public key in `authorized_keys` format.
- `payload.name` and `data.session_ref` must both be the terminal's session reference. `target_user` is always
  `nixstasis-support`.
- `ttl_seconds` is positive and at most `3,600`, the one-hour limit on any terminal.
- The client accepts only this exact versioned content type, and keeps the key only in memory. A client restart, the
  time limit, or a revoke all remove it.

The server creates the session reference and queues this command before anything else, and the browser gets no
terminal socket token until the command's result is `OK`. When the browser joins, the terminal channel needs the
matching command ID, and checks the command type, device, content type, and session reference again before starting
SSH. If authorization fails or takes too long, the server drops the session and the browser stops retrying.

Resizing the terminal accepts rows and columns from `1` to `1,000`. The channel waits for a burst of resizes to settle
and passes on only the latest size. The server's SSH client also runs only one resize at a time; while one runs, newer
requests are folded into the latest size. That stops a flurry of resizes from starting endless SSH processes. If a
resize crashes, the client remembers the last size that worked, so trying the same size again still runs. Each resize
has a 15-second deadline, plus SSH connect and keepalive limits; one that stalls past the deadline is stopped, and the
latest waiting size runs next.

### `ssh_revoke`

When a terminal closes, times out, loses its device, or fails after the session was created, the server tries to queue
a revoke. It is safe to send more than once:

```json
{
  "command_id": "<uuid>",
  "type": "ssh_revoke",
  "payload": {
    "content_type": "application/vnd.nixstasis.ssh-revoke+json;version=1",
    "name": "<session-ref>",
    "data": "{\"session_ref\":\"<session-ref>\"}"
  }
}
```

Each revoke goes to one device, and repeated attempts for the same session are merged into one. The server cleans up
its own copy of the key even if the revoke cannot be queued. A failed join with an unknown session reference sends no
revoke, and a client that receives a revoke for a session it does not know simply ignores it.

The client and the root-owned `AuthorizedKeysCommand` wrapper talk over the fixed local socket
`/run/nixstasis/ssh-authority.sock`. The helper reads no general client config and never takes a socket path from a
request. Installs use three accounts: `nixstasis-support` for terminals, `nixstasis` for the service, and the locked
`nixstasis-ssh-authority` account for the helper.

## Operator Role Contract

- **Gateway:** Caddy and AuthCrunch authenticate operators. Protected hosts use `authorize with entra_policy`, except
  `frp-admin.<base-domain>`, which uses `frp_admin_policy`: it admits only `nixstasis/admin` and injects no claims.
- **Role mapping:** AuthCrunch maps the provider groups in `NIXSTASIS_VIEWER_GROUPS`, `NIXSTASIS_OPERATOR_GROUPS`, and
  `NIXSTASIS_ADMIN_GROUPS` to provider-independent roles before Phoenix sees the request.
- **Claim headers:** Phoenix reads `X-Token-Subject`, `X-Token-User-Email`, `X-Token-User-Name`, and
  `X-Token-User-Roles`, and only with a valid `X-Nixstasis-Proxy-Token`. Client-supplied `X-Token-*` headers are
  removed before AuthCrunch injects verified ones.

Capabilities come from `@role_capabilities` in `packages/server/lib/nixstasis_web/operator_context.ex`:

| Capability                                        | `nixstasis/viewer` | `nixstasis/operator`        | `nixstasis/admin`           |
|---------------------------------------------------|--------------------|-----------------------------|-----------------------------|
| View devices, reports, alerts, and scripts        | Yes                | Yes                         | Yes                         |
| Manage devices, reports, alert rules, and scripts | No                 | Yes                         | Yes                         |
| Remote access to devices                          | No                 | Yes                         | Yes                         |
| Command policies                                  | Status only        | Full details and management | Full details and management |
| Global system settings                            | No                 | No                          | Yes                         |
| FRPS dashboard                                    | No                 | No                          | Yes                         |

- **No role, no access:** in production, a missing, malformed, or unknown role grants nothing. Only in the dev and test
  environments does a request without claim headers get default development permissions.
- **Device scope** never comes from the identity provider. Phoenix ignores `X-Token-Device-Ids`, and the older
  `X-Token-Device-Id` and `X-Token-Allowed-Device-Ids`, and Caddy forwards no `device_ids` claim, so a role covers the
  whole fleet. When Phoenix permissions do carry a scope, device reads and changes, active alerts, and dashboard counts
  are limited to it, an empty scope returns nothing, and without permission to view devices you see nothing. Creating
  devices, and writing commands or telemetry across many devices at once, needs manage permission with no scope
  restriction.
- **Separate credentials:** the `/api/json` operator API never accepts device runtime tokens.
