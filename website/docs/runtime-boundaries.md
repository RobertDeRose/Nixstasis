# Runtime Boundaries

Where each part of Nixstasis runs, what it trusts, and how it is kept apart from the rest. How each component works
inside is covered in the [Module Reference](modules/index.md).

## Processes

- **Phoenix** runs as one OTP release. Stateful work runs in supervised processes
  ([Server Application](modules/server-application.md)); each browser terminal session is its own `SshClient` process
  that wraps an OS `ssh` command through an Elixir Port.
- **The client** runs `nixstasis poll` as a long-running service that loops on a ticker. Scripts run concurrently,
  and commands run concurrently unless they change files, keys, or policy.
- **`frpc`** runs only while remote access is granted, as a transient systemd unit or a poll-owned `frp-session` child,
  with a one-hour timeout ([Client FRP Manager](modules/client-frp-manager.md)).
- **Caddy, FRPS, and PostgreSQL** run as Compose services ([Deployment](operations/deployment.md)).

## Untrusted inputs

| Input                        | Enters through                         | Trusted after                                                                                                                                    |
|------------------------------|----------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| Operator actions             | LiveViews and controllers behind Caddy | AuthCrunch authentication, the proxy credential, and Phoenix role and scope checks ([Server Web](modules/server-web.md)).                        |
| Device requests              | `/api/v1/devices/...`                  | Device token authentication; registration is public but proves possession of client-saved secrets ([Server Devices](modules/server-devices.md)). |
| Device telemetry             | Heartbeats                             | Size and shape validation before any side effect ([Server Monitoring](modules/server-monitoring.md)).                                            |
| JSON:API requests            | `/api/json`                            | AuthCrunch, then route and data-layer policies ([Server Domain](modules/server-domain.md)).                                                      |
| E2E requests                 | `/e2e`                                 | The E2E gate and runner authentication ([Server E2E](development/e2e/server.md)).                                                                |
| Certificate requests         | Caddy's `check_domain` ask             | Phoenix approval for a device with an active lease.                                                                                              |
| Laptop TLS diagnostics       | `/_nixstasis/laptop/tls_observations`  | A development-only token; not a product API.                                                                                                     |
| Scripts and command policies | Local files and server commands        | Client-side parsing, schema checks, and execution limits ([Client Starlark Runtime](modules/client-starlark-runtime.md)).                        |

Phoenix ignores forwarded identity headers and the client-IP header unless the request also carries the secret
credential Caddy adds, so nobody can fake them by calling Phoenix directly. Device scope is never taken from identity
claims at all.

## Browser terminal authorization

A browser terminal passes through four parties, and each one has to agree before a session opens:

1. **Phoenix** checks the operator's remote-access permission, generates an ephemeral key pair, creates a session
   reference, and queues `ssh_authorize` for the device. It activates the browser token only after the device reports
   success, and queues `ssh_revoke` on close, expiry, or failure.
2. **The client** validates the authorization and keeps the public key only in its in-memory SSH authority, never on
   disk.
3. **The OpenSSH helper**, `nixstasis ssh-authorized-keys`, runs as the locked `nixstasis-ssh-authority` user. It
   validates `%u %t %k`, asks the client over `/run/nixstasis/ssh-authority.sock`, and prints a key only on an exact
   allow. It cannot run client commands and has no file fallback.
4. **OpenSSH** authenticates the `nixstasis-support` account with `AuthorizedKeysFile none`. FRP only carries the
   connection.

Because the key only ever lives in the client's memory, a client restart, an expired or revoked session, or a broken
socket all end in the same place: access denied. On the server, each session keeps its
private key and pinned host key in a `0700` temporary directory with `0600` files, and connects with `ssh` through an
`ncat` HTTP proxy to the FRPS TCP mux. The wire format is in
[API & Runtime Contracts](reference/contracts.md#browser-terminal-ssh-authorization-contract).

## Network exposure

| Service    | Exposure                                                                                                       |
|------------|----------------------------------------------------------------------------------------------------------------|
| Caddy      | Ports 80 and 443 on `BIND_HOST`: the only public HTTP ingress.                                                 |
| FRPS       | `FRPS_BIND_PORT` on `BIND_HOST` for device tunnels; its HTTP vhost, TCP mux, and dashboard ports are internal. |
| Phoenix    | `PORT` on `PHOENIX_BIND_HOST`, which stays `127.0.0.1` in production, for local diagnostics only.              |
| PostgreSQL | Internal, unless `DATABASE_URL` points at an external database.                                                |

Devices call the server at the configured `api.url`, normally `https://nixstasis.<base-domain>` through Caddy. Caddy
reaches Phoenix and FRPS on the internal Compose network, and FRPS reaches Phoenix's `/internal/frp` plugin endpoint the
same way.
