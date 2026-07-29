# Server-Provided FRPS Token Tasks

## Setup

- [x] T000 Confirm the active worktree is `feat/server-provided-frps-token` and
  the feature spec matches the intended heartbeat-provided FRPS token contract.
- [x] T000a Rebase or merge `main` before implementation so this branch includes
  the completed self-extracting-installer docs and systemd credential model.

## Contract And Deployment

- [x] T001 Update `deploy/compose/docker-compose.yml` so the `nixstasis` service
  receives `FRPS_AUTH_TOKEN` in addition to the `frps` service.
- [x] T002 Update `deploy/compose/scripts/check_runtime_contract.sh` to assert
  that `FRPS_AUTH_TOKEN` is wired into both `frps` and `nixstasis` runtime
  configuration.
- [x] T003 Update
  `docs/src/modules/deployment-compose.md`
  to document `FRPS_AUTH_TOKEN` as consumed by both services.
- [x] T004 Update `docs/src/client-server-interface.md` to
  replace `remote_access_requested` with `remote_access_token` in the heartbeat
  response schema.

## Server Implementation

- [x] T005 Add a small server helper for resolving the heartbeat FRPS token from
  `FRPS_AUTH_TOKEN` only when `device.remote_access_requested` is true.
- [x] T006 Update `HeartbeatJSON.show/1` to emit `remote_access_token` instead of
  `remote_access_requested`.
- [x] T007 Add or update heartbeat controller tests for token absent when remote
  access is not requested.
- [x] T008 Add heartbeat controller coverage for token present when remote access
  is requested and `FRPS_AUTH_TOKEN` is configured.
- [x] T009 Add heartbeat controller coverage for remote access requested with
  missing `FRPS_AUTH_TOKEN`, matching the selected omit-token/log-error behavior.

## Client Implementation

- [x] T010 Update `transport.PollResponse` to use `RemoteAccessToken string`
  mapped to `remote_access_token`.
- [x] T011 Update `pollOnce` to start FRPC when `RemoteAccessToken` is non-empty
  and set `frpConfig.AuthToken` from that response token.
- [x] T012 Update `pollOnce` to stop FRPC when `RemoteAccessToken` is empty and
  FRPC is currently active.
- [x] T013 Ensure `runtimeFRPConfig` does not derive or fallback auth tokens from
  device runtime credentials.
- [x] T014 Update client poll/transport tests for token-present and token-absent
  behavior.
- [x] T015 Keep FRP manager validation requiring a non-empty auth token for actual
  starts.
- [x] T015a Confirm client start behavior still passes the token via systemd
  `LoadCredential`, not `systemd-run --setenv`.
- [x] T015b Update FRP manager comments so `--setenv` is documented as carrying
  only non-secret frpc template values, while `FRPS_AUTH_TOKEN` uses systemd
  credentials.

## Documentation

- [x] T015c Update `packages/client/README.md` so operator guidance no longer
  treats `frp.auth_token` as the normal remote-access token source.
- [x] T015d Update `docs/src/modules/client-frp-manager.md` so heartbeat response
  docs describe `remote_access_token`, not `remote_access_requested`.
- [x] T015e Update `docs/src/modules/edge-frp.md` so FRP interaction docs describe
  server-provided token start/stop behavior and systemd credentials.
- [x] T015f Update `docs/src/runtime-boundaries.md` if the client/server trust or
  process boundaries need new FRPS token wording.
- [x] T015g Ensure `docs/src/planned-features.md` records this reviewed feature
  accurately.

## Test Support

- [x] T015h Update `packages/client/scripts/mock_api/main.go` so test/dev polling
  can return `remote_access_token` instead of `remote_access_requested`.

## Verification

- [x] T016 Run client tests with `GOEXPERIMENT=jsonv2 go test -race ./...` from
  `packages/client`.
- [x] T017 Run targeted server tests for heartbeat response behavior.
- [x] T018 Run `mix precommit` from `packages/server` after server changes.
- [x] T019 Run the compose runtime contract checker.
- [x] T020 Review diffs to ensure no FRPS token is persisted to client config,
  identity, logs, or docs as a client-owned static value.
- [x] T021 Search docs and code for stale heartbeat response references to
  `remote_access_requested`; keep device state references only where they still
  describe server-side persisted intent.

## Completion

- [x] T999 Confirm implementation, docs/contracts, and tests agree; summarize any
  intentional follow-up work such as per-device FRPS auth.
