# Tasks: Go Client Rewrite

## Final-State Checklist

- [x] Provide a single `nixstasis` Go binary with registration, polling, script,
  command, FRP, and support workflows.
- [x] Load client configuration from `/etc/nixstasis/config.yaml` with supported
  environment overrides.
- [x] Detect stable device identity from host network interfaces and persist the
  server-assigned device ID/API credential.
- [x] Register devices through the Phoenix `/api/v1/devices/register` API and
  handle pending approval without issuing runtime credentials prematurely.
- [x] Poll the server through token-authenticated heartbeat requests and submit
  telemetry plus FRPC connection state.
- [x] Use Starlark `.stary` scripts as the supported telemetry extension model.
- [x] Execute server-issued command batches and return correlated command results.
- [x] Start, stop, and restart FRPC based on heartbeat-provided
  `remote_access_token` values.
- [x] Avoid persisting the shared FRPS token in static client configuration or
  identity files.
- [x] Build and validate supported Linux release artifacts, including packages
  with bundled `frpc`.
