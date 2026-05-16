# Runtime Boundaries

## Process Boundaries

### Elixir/OTP Processes

- `Nixstasis.Application` starts the OTP supervision tree.
- `NixstasisWeb.Endpoint` owns HTTP, WebSocket, LiveView, and Channel request handling.
- `Nixstasis.Repo` owns database connections.
- `Phoenix.PubSub` is supervised as `Nixstasis.PubSub`.
- `Nixstasis.Monitoring.OfflineChecker` is a named GenServer that schedules `:check` messages every 60 seconds.
- `Nixstasis.E2E.RetentionWorker` is a named GenServer that schedules E2E retention pruning.
- `Nixstasis.Devices.SshClient` is a GenServer per terminal session and wraps an OS `ssh` process through an Elixir Port.

Traceable references:

- `packages/server/lib/nixstasis/application.ex:10-29`
- `packages/server/lib/nixstasis/monitoring/offline_checker.ex:13-31`
- `packages/server/lib/nixstasis/e2e/retention_worker.ex:14-50`
- `packages/server/lib/nixstasis/devices/ssh_client.ex:9-94`

### Go Runtime

- The client binary entry point is `cmd/nixstasis/main.go`.
- The root command is a Cobra command named `nixstasis`.
- Client configuration is loaded during `PersistentPreRunE`, except for `script test` and `script repl` command paths.
- `runMain` starts a Go runtime flight recorder before executing the root command.
- `poll` creates a ticker from configured poll interval and repeatedly calls `pollOnce`.
- `script.Executor` runs discovered scripts concurrently with goroutines and a `sync.WaitGroup`.
- `commands.Handler` executes batches concurrently where command type allows it.
- `frp.Manager` launches a `nixstasis-frpc` transient systemd unit with
  `systemd-run`; that unit runs the hidden `nixstasis frp-session` subcommand,
  which starts the bundled `frpc` process with a one-hour timeout.

Traceable references:

- `packages/client/cmd/nixstasis/main.go:20-98`
- `packages/client/cmd/nixstasis/poll.go:35-83`
- `packages/client/internal/script/executor.go:23-48`
- `packages/client/internal/commands/handler.go:27-76`
- `packages/client/internal/frp/manager.go`
- `packages/client/cmd/nixstasis/frp_session.go`

### Starlark Execution Environment

- `script.Runtime` executes Starlark scripts using `go.starlark.net/starlark`.
- Runtime builtins include `pub_and_get`, `exec_cmd`, and `json`.
- `Runtime.Execute` creates a Starlark thread named `stary` and executes a parsed script body.
- Scripts must define a callable `main()`.
- `main()` output is converted from Starlark values to Go values and must be a dictionary when non-null.
- Runtime execution is bounded by `RuntimeConfig.Timeout`; timeout cancels the Starlark thread.

Traceable references:

- `packages/client/internal/script/runtime.go:20-47`
- `packages/client/internal/script/runtime.go:73-128`
- `packages/client/internal/script/runtime.go:130-179`
- `packages/client/internal/script/builtins_exec.go`
- `packages/client/internal/script/builtins_mqtt.go`

## Trust Boundaries

### User Input

- Browser form and event inputs enter through Phoenix LiveViews and controllers.
- Device API inputs enter through Phoenix JSON controllers under `/api/v1`.
- Ash JSON:API inputs enter through `/api/json` forwarded to `NixstasisWeb.AshJsonApiRouter`.
- E2E API inputs enter through `/e2e` routes when E2E is enabled.
- Caddy on-demand TLS sends domain approval input to `GET /api/v1/check_domain`.

Traceable references:

- `packages/server/lib/nixstasis_web/router.ex:22-79`
- `packages/server/lib/nixstasis_web/controllers/tls_controller.ex:7-27`

### Script Execution

- Stary/Starlark scripts are external script content read from configured script directories or installed command payloads.
- Script installation validates front matter and JSON schema before writing installed script files.
- Script execution runs with Starlark builtins that can interact with MQTT.
- OS command execution through `exec_cmd` is deny-by-default and only available
  when the client runtime configuration maps a requested command name to an
  absolute allowlisted executable path.
- Script results become telemetry payload fields sent to the server.

Traceable references:

- `packages/client/internal/script/executor.go:50-93`
- `packages/client/internal/script/runtime.go:40-44`
- `packages/client/internal/commands/handler.go:132-187`
- `packages/client/cmd/nixstasis/poll.go:105-126`

### External Access Through FRP

- FRPC runs on managed devices and connects to FRPS.
- FRPS exposes tunnel transport ports from the Compose deployment.
- Caddy proxies wildcard `*.{$BASE_DOMAIN}` traffic to FRPS HTTP vhost port.
- Caddy proxies `frp-admin.{$BASE_DOMAIN}` to the FRPS dashboard port.
- Server-side SSH terminal sessions use `ssh` with an `ncat` HTTP proxy command pointed at the configured FRP host and TCP mux port.
- Development laptop mode uses the same Caddy, Phoenix, FRPS, FRPC, and SSH
  process boundaries with `localhost` as the base domain and Caddy internal/local
  certificates for TLS.
- The `client` container is a device simulator running systemd as PID 1 with sshd,
  frpc, and the Go client binary; FRPC connects through FRP and the browser
  terminal reaches SSH through FRPS TCP mux.

Traceable references:

- `deploy/compose/docker-compose.yml:33-66`
- `deploy/compose/frps/frps.toml:1-15`
- `deploy/compose/caddy/Caddyfile:59-75`
- `packages/server/lib/nixstasis/devices/ssh_client.ex:30-49`

## Network Boundaries

### Caddy to Phoenix

- Public host `nixstasis.{$BASE_DOMAIN}` terminates TLS at Caddy and reverse proxies to `nixstasis:4000`.
- Caddy on-demand TLS asks Phoenix at `http://nixstasis:4000/api/v1/check_domain`.
- Compose publishes only Caddy ports `80` and `443` for the main HTTP ingress.
- Default laptop mode maps the same host pattern to `.localhost` names:
  `nixstasis.localhost`, `auth.localhost`, `frp-admin.localhost`, and
  `atom-<normalized-device-id>.localhost`.
- Laptop mode also publishes Phoenix on `127.0.0.1:4000` for local-only
  validation diagnostics; deployment-shaped browser access still goes through
  Caddy.

Traceable references:

- `deploy/compose/caddy/Caddyfile:8-10`
- `deploy/compose/caddy/Caddyfile:50-57`
- `deploy/compose/docker-compose.yml:14-31`

### Client to Server

- The Go client uses HTTP JSON requests to the configured `api.url`.
- Default client API URL is `http://localhost:4000`.
- Packaged configuration documentation uses `https://nixstasis.example.com` as the public Caddy host.

Traceable references:

- `packages/client/internal/config/config.go:62-64`
- `packages/client/README.md:115-128`
- `packages/client/internal/transport/client.go:27-35`

### Internal Services

- `nixstasis` service listens on `PORT=4000` inside the Compose network; Caddy
  is the public HTTP(S) ingress.
- `postgres` is always included; production can override `DATABASE_URL` to use
  an external managed database.
- `frps` is reached by Caddy on internal service ports and by FRPC on published FRP ports.

Traceable references:

- `deploy/compose/docker-compose.yml:1-129`
- `deploy/compose/README.md:1-117`
