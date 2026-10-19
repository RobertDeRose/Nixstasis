# Client FRP Manager

Starts and stops the bundled `frpc` when the server grants remote access, renders the device's own route profiles, and
reports tunnel state back in heartbeats.

## Owns

- `packages/client/internal/frp/`: the `Manager` (`manager.go`), route rendering (`render.go`), and route and status
  types (`types.go`).
- The client-owned route profiles in `/etc/nixstasis/config.yaml`, rendered into a temporary `frpc.toml` for each
  session.

## Entry points

- `NewManager` creates the manager. `Start` and `Stop` run and end a tunnel, `IsActive` and `GetStatus` report its
  state, and `SetError` records a failure for the next heartbeat.
- The poll loop drives it from each heartbeat response:
  - If a `remote_access_token` arrives and no tunnel is running, it starts `frpc` with the named
    `remote_access_profile`. A token without a profile is refused.
  - If the token is missing or empty while a tunnel is running, it stops `frpc`.
  - The next heartbeat reports the tunnel's state back to the server as `connection_status`.

## Boundaries

- **Process model:** root-managed installs run `frpc` as the `nixstasis-frpc` transient systemd unit. When the poll
  service cannot reach the system manager, as in the Compose simulator, it runs the hidden `nixstasis frp-session`
  child with the same timeout instead.
- **Credentials:** the signed FRPS credential reaches `frpc` through a root-only environment file as `FRPS_AUTH_TOKEN`,
  and is sent only as FRPS plugin metadata, never as the shared transport token.
- **Restarts:** a new token with only a different signature does not restart `frpc`. A change of profile or lease
  restarts it promptly. The stored credential is replaced when its expiry moves earlier, or when a later expiry arrives
  within 30 seconds of the current one. An expired credential stops `frpc`. The lease rules are in
  [Server Devices](server-devices.md).
- **The device defines its routes:** the server only names a profile; it never sends route definitions, headers, or
  plugin options. An unknown profile, an unsupported version, a target that is not on loopback, or an unsupported
  route kind means no tunnel starts, and the error is reported in `connection_status.error` until remote access is
  withdrawn.
- **Route rules:** route identifiers must be DNS-safe because HTTP subdomains and TCP mux domains are built from them.
  HTTP routes may rewrite the `Host` header only to `localhost` or a loopback IP; the built-in `atomixos-bootstrap`
  profile sends `localhost` to `127.0.0.1:8080`. Profile version 1 covers today's routes; new route semantics
  need a new version.
- The server side of FRP authorization is described in [Gateway FRP](gateway-frp.md).
