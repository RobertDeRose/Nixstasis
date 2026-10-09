# Client FRP Manager

## Language

- Go.

## Runtime Context

- Client launcher for the bundled `frpc` transient systemd unit.

## Purpose

- Starts/stops the FRPC transient systemd unit, renders only client-owned typed
  routes, checks connection state through systemd, and reports state to heartbeat
  payloads.

## Key Files

- `packages/client/internal/frp/manager.go`
- `packages/client/internal/frp/types.go`
- `packages/client/internal/frp/manager_test.go`
- `packages/client/cmd/nixstasis/frp_session.go`
- `packages/client/cmd/nixstasis/frp_session_test.go`
- `packages/client/build/root-dir/usr/share/nixstasis/frpc.toml`
- `packages/client/build/root-dir/usr/share/nixstasis/config.example.yaml`
- `packages/client/internal/config/config.go`
- `packages/client/internal/config/route_profile.go`
- `packages/client/internal/frp/render.go`
- `packages/client/cmd/nixstasis/poll.go`

## Public Interfaces

- Types:
  - `Manager`
  - `ConnectionStatus`
- Functions and methods:
  - `NewManager`
  - `(*Manager).Start`
  - `(*Manager).Stop`
  - `(*Manager).IsActive`
  - `(*Manager).GetStatus`
  - `config.FRPCBinaryPath`
  - `config.FRPCConfigPath`

## Dependencies

### Internal

- `internal/config`

### External

- OS process execution via `os/exec`.
- systemd transient units via `systemd-run` and `systemctl`.

## Client-Server Interaction Details

- Heartbeat responses include `remote_access_token`, the selected durable
  `remote_access_lease_id`, its Unix-millisecond `remote_access_expires_at_ms`,
  and the optional versioned `remote_access_profile`
  reference only while the device has an active authorization.
- If `remote_access_token` is non-empty and FRP is inactive, `pollOnce` resolves
  the named profile against client configuration, then starts the `nixstasis-frpc`
  transient unit using typed local routes and the heartbeat token. A token-only
  legacy response selects the local `default` profile.
- If `remote_access_token` is absent or empty and FRP is active, `pollOnce` stops
  FRPC.
- A changed signature alone does not restart FRPC. The client replaces its stored
  credential when validity is shortened or a later expiry is available within
  30 seconds of the stored expiry. Profile or lease identity changes trigger a
  bounded restart, including same-profile lease replacement with a later expiry.
  An already-expired advertised credential stops FRPC.
- Unknown profile names, unsupported versions, non-loopback targets, and
  unsupported route/plugin kinds fail closed; the error is included in the next
  `connection_status.error` report and is cleared when remote access is withdrawn.
- Version 1 is the compatibility boundary for typed route kinds and controlled
  loopback targets. Future capabilities require client-declared typed support,
  security review, and a new profile version when route semantics change; the
  server never supplies route definitions, headers, or plugin options.
- FRP status is included in subsequent heartbeat requests as `connection_status`.
- Route profiles remain client-owned in `/etc/nixstasis/config.yaml`; the
  client renders a temporary typed `frpc.toml` and frpc expands its server/auth
  placeholders from the session environment. Route identifiers and the derived
  proxy names must be DNS-safe because HTTP subdomains and TCP mux custom domains
  are rendered from them. Plain HTTP routes may optionally set a Host-header
  rewrite, but only to `localhost` or a loopback IP; the built-in
  `atomixos-bootstrap` profile uses `localhost` for its `127.0.0.1:8080` route.
- FRPS wire proxy names include the authenticated user prefix. Phoenix removes
  only that exact prefix before checking the device-owned raw route name/domain.
  Login and NewProxy also check the exact selected durable lease and its profile,
  so a revoked credential cannot borrow another owner's active authorization.
  Established tunnels stop on the next authenticated heartbeat, not synchronously
  through the authorization callback.
- The signed FRPS device credential is passed to the transient unit through a
  root-only environment file and exposed to frpc as `FRPS_AUTH_TOKEN`; the FRPC
  template sends it only as FRPS plugin metadata, not as the shared transport token.
- If an unprivileged poll service is denied access to the system manager (as in
  the nested systemd Compose client), the manager starts a poll-owned
  `frp-session` child with the same bounded timeout and stops it when remote
  access is withdrawn. Native root-managed systemd installations retain the
  transient-unit path.

Traceable references:

- `packages/client/internal/frp/manager.go`
- `packages/client/cmd/nixstasis/frp_session.go`
- `packages/client/cmd/nixstasis/poll.go`
- `packages/client/internal/config/config.go`
- `packages/client/internal/config/route_profile.go`
