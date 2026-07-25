<!-- workflow-migration:legacy-markdown-to-beads -->

# Server-Provided FRPS Token

## Summary

Replace the remote-access heartbeat response boolean with a token-bearing
contract. When the server wants a managed client to open remote access, the
heartbeat response includes the shared FRPS auth token. The client treats a
non-empty token as the start signal, passes that token to the transient unit as
a systemd credential, and stops FRPC when no token is provided.

## Goals

- Make the heartbeat response the source of truth for both remote-access intent
  and the FRPS auth token needed to satisfy the current upstream FRPS token auth
  deployment.
- Keep the device runtime API token separate from the FRPS auth token.
- Avoid persisting the FRPS token in client config or identity files.
- Keep the client-owned `frpc.toml` template and frpc-native
  `{{ .Envs.FRPS_AUTH_TOKEN }}` expansion model.
- Keep FRPC lifecycle owned by the `nixstasis-frpc` transient systemd unit.

## Non-Goals

- Implementing per-device FRPS tokens.
- Adding an FRPS auth plugin or replacing upstream token authentication.
- Changing UI permissions for opening or closing remote access.
- Changing the terminal channel or browser authorization model.
- Persisting the FRPS token on client hosts.

## Pre-Implementation Behavior

- The Phoenix heartbeat response includes `remote_access_requested: boolean`.
- The Go client starts FRPC when `remote_access_requested` is true.
- FRPC receives its auth token from client runtime config (`frp.auth_token`).
- Compose configures FRPS with a single shared `FRPS_AUTH_TOKEN`.
- The Phoenix `nixstasis` service does not currently receive `FRPS_AUTH_TOKEN`.

## Proposed Contract

Heartbeat response data changes from:

```json
{
  "data": {
    "remote_access_requested": true,
    "commands": []
  }
}
```

to:

```json
{
  "data": {
    "remote_access_token": "<shared-frps-token>",
    "commands": []
  }
}
```

Semantics:

- `remote_access_token` non-empty: start or keep FRPC running with that token.
- `remote_access_token` omitted: stop FRPC if active; otherwise remain stopped.
- `remote_access_token` may decode as an empty string on older or malformed
  responses; the client treats that the same as omission.
- `remote_access_requested` is removed from the client response contract because
  no release has shipped with the current branch behavior.

## Server Design

- Compose passes `FRPS_AUTH_TOKEN` to both services:
  - `frps`: uses it in `frps.toml` as `auth.token`.
  - `nixstasis`: uses it only to populate authenticated heartbeat responses when
    `device.remote_access_requested` is true.
- Add a small helper that resolves the heartbeat FRPS token from `FRPS_AUTH_TOKEN`
  only when `device.remote_access_requested` is true.
- Keep `HeartbeatJSON.show/1` focused on rendering response data. It receives or
  calls the helper result and conditionally includes `remote_access_token`:

Remote access token rendering cases:

- Absent when `device.remote_access_requested` is false.
- Configured `FRPS_AUTH_TOKEN` when `device.remote_access_requested` is true.
- If remote access is requested but `FRPS_AUTH_TOKEN` is missing, the heartbeat
  should continue returning telemetry/command responses and omit the token. The
  helper should log a clear error so the UI timeout is diagnosable.

## Client Design

- `transport.PollResponse` replaces `RemoteAccessRequested bool` with
  `RemoteAccessToken string`.
- `pollOnce` starts FRPC when `resp.RemoteAccessToken != ""`.
- Before `Manager.Start`, `pollOnce` derives runtime FRP config from the local
  config and MAC address, then sets `frpConfig.AuthToken = resp.RemoteAccessToken`.
- `runtimeFRPConfig` derives only dynamic client-owned values, such as FRP proxy
  name from MAC when `frp.name` is not configured.
- `pollOnce` stops FRPC when `resp.RemoteAccessToken == ""` and current FRP
  status is active.
- `Manager.Start` continues validating that the final FRP config has a non-empty
  auth token before invoking `systemd-run`.
- `Manager.Start` continues passing the token to the transient unit through
  `LoadCredential=FRPS_AUTH_TOKEN:<path>`; it must not pass the token through
  `systemd-run --setenv` metadata.

## Security Notes

- The shared FRPS token is exposed to authenticated managed devices only when an
  operator has requested remote access for that device.
- This preserves the current upstream FRPS token auth model, but shared-token
  revocation remains all-or-nothing.
- Per-device revocation and token audit are explicitly deferred to a future FRPS
  auth-plugin feature.

## Docs And Contracts Affected

- `docs/src/client-server-interface.md`
- `docs/src/modules/deployment-compose.md`
- `deploy/compose/scripts/check_runtime_contract.sh`
- `deploy/compose/docker-compose.yml`
- `deploy/compose/README.md`
- `packages/server/README.md`
- `packages/client/README.md`
- `packages/client/scripts/mock_api/main.go`
- `packages/client/internal/frp/manager.go`
- `docs/src/modules/client-frp-manager.md`
- `docs/src/modules/edge-frp.md`
- `docs/src/runtime-boundaries.md`
- `docs/src/planned-features.md`

## Validation

- Server tests prove heartbeat omits `remote_access_token` when remote access is
  false.
- Server tests prove heartbeat includes `FRPS_AUTH_TOKEN` when remote access is
  true and the env var is configured.
- Server tests prove heartbeat omits `remote_access_token` and logs a clear error
  when remote access is requested but `FRPS_AUTH_TOKEN` is missing.
- Client tests prove a non-empty `remote_access_token` starts FRPC using that
  token.
- Client tests prove an empty/missing token stops FRPC when active.
- Runtime contract checks prove the Phoenix service receives `FRPS_AUTH_TOKEN`.
- Client README no longer tells operators to configure a static `frp.auth_token`
  for normal server-requested remote access.
- Mock API flags and fixtures use `remote_access_token` for client-side testing.
- FRP manager comments distinguish non-secret template values passed by `--setenv`
  from the secret token passed through systemd credentials.
- Docs and module pages no longer describe `remote_access_requested` as the
  heartbeat response trigger after implementation.
- Existing client tests continue to pass with `GOEXPERIMENT=jsonv2 go test -race
  ./...`.
- Server precommit checks pass with `mix precommit`.

## Reconciliation Bookends

- Before implementation, rebase or merge `main` so the completed
  `self-extracting-installer` docs and systemd credential model are present.
- During implementation, update server, client, deployment contract, and docs in
  the same unit of work so `remote_access_requested` is no longer documented as a
  heartbeat response field.
- Before completion, rerun the affected docs search for `remote_access_requested`,
  `remote_access_token`, and `FRPS_AUTH_TOKEN` and reconcile any remaining stale
  references.
