# Tasks: Go Client Rewrite

## Final-State Checklist

- [x] `T001` Provide a single `nixstasis` Go binary with registration, polling, script,
  command, FRP, and support workflows.
- [x] `T002` Load client configuration from `/etc/nixstasis/config.yaml` with supported
  environment overrides.
- [x] `T003` Detect stable device identity from host network interfaces and persist the
  server-assigned device ID/API credential.
- [x] `T004` Register devices through the Phoenix `/api/v1/devices/register` API and
  handle pending approval without issuing runtime credentials prematurely.
- [x] `T005` Poll the server through token-authenticated heartbeat requests and submit
  telemetry plus FRPC connection state.
- [x] `T006` Use Starlark `.stary` scripts as the supported telemetry extension model.
- [x] `T007` Execute server-issued command batches and return correlated command results.
- [x] `T008` Start, stop, and restart FRPC based on heartbeat-provided
  `remote_access_token` values.
- [x] `T009` Avoid persisting the shared FRPS token in static client configuration or
  identity files.
- [x] `T010` Build and validate supported Linux release artifacts, including packages
  with bundled `frpc`.
