# Welcome to Nixstasis

Nixstasis is an IoT monitoring and remote access platform. The current supported
server deployment path for this feature is Docker Compose via `deploy/compose`.

The client and server have been rewritten from their original Bash and Python/Reflex implementations into Go and
Elixir/Phoenix, respectively.

## Key Components

- **Client (Go)**: Lightweight agent that registers devices, polls telemetry plugins, and manages FRP tunnels.
- **Server (Elixir/Phoenix + LiveView)**: API and web UI for device monitoring, approvals, alerts, and reporting.
- **Packaging and Release**: OCI image builds for server/Caddy and a GoReleaser
  client packaging flow are being introduced as the supported path for this
  migration.
- **Infrastructure**: [`FRP`](https://gofrp.org/en/), [`Caddy`](https://caddyserver.com/), and
  [`AuthCrunch`](https://authcrunch.com) integrate to provide secure, on-demand remote access.

## Repository Structure

- `packages/client`: Go-based client agent.
- `packages/server`: Phoenix server application.
- `deploy/compose`: Supported server deployment assets for this migration.
- `packages/caddy`: Caddy image and legacy packaging assets.
- `packages/frp`: Debian packaging for FRP.
- `specs`: Feature specs and task checklists for the rewrites and ongoing work.

## Package READMEs

- Client: [`packages/client/README.md`](packages/client/README.md)
- Server: [`packages/server/README.md`](packages/server/README.md)

## Deployment status

- Supported server deployment path: `deploy/compose`
- Supported client release path: GoReleaser from `packages/client`
- Abandoned server package deployment assets are not part of the supported
  release path for this migration.

## Client release status

Build client snapshot artifacts from `packages/client` with the tracked
production version pins:

```bash
grep -E '^(FRP_VERSION|CADDY_VERSION|POSTGRES_VERSION)=' prod.env
goreleaser release --snapshot --clean
./scripts/release/verify_artifacts.sh
```

The supported client artifacts install `nixstasis` to `/usr/bin/nixstasis` and the bundled `frpc` runtime to `/usr/libexec/nixstasis/frpc`.

## E2E Tests (Client ↔ Server)

This repo includes a client-driven E2E harness:

- The client executes journeys and emits structured JSON logs.
- The server validates contracts, seeds baseline data, stores runs/results/log refs, and renders reports in
  LiveDashboard.

### Quick Start

Prerequisites:

- Server is running from `packages/server` (for example: `mix phx.server`).
- Server migrations are up to date.
- You run the harness from `packages/client`.

Run full suite:

```bash
cd packages/client
scripts/e2e/run --suite full --env local --trigger manual --protocol-version 1
```

Run one journey:

```bash
cd packages/client
scripts/e2e/run --journey auth --env local --trigger manual --protocol-version 1
```

Run with idempotent create semantics (1-hour window scoped by environment):

```bash
cd packages/client
scripts/e2e/run --suite full --env local --trigger manual --protocol-version 1 --idempotency-key local-full-001
```

Inspect results:

- API: `/e2e/runs`, `/e2e/runs/:id`, `/e2e/runs/:id/results`, `/e2e/runs/:id/results/:journey_id/log`
- Suite catalog API: `/e2e/suites` (server source of truth for available suites)
- LiveDashboard: `/dev/dashboard/e2e`

### Contract Rules (Server-Enforced)

- `POST /e2e/runs` requires `X-E2E-Protocol-Version` header.
- `client_version`/`server_version` request fields are rejected (immediate break).
- `trigger_source` accepts `manual|ci` and is reporting metadata only.
- Idempotency applies to run creation only: `(environment_label, idempotency_key)` with 1-hour TTL.
- Only one active run per environment is allowed at a time (`409 environment_locked`).
- Run creation fails if baseline seed fails (`422 seed_failed`).
- Action/expect pairs are validated by server-side registry before accepting run execution (`400
  invalid_action_expectation`).

### Execution Model

1. Client loads config and journey specs.
2. Client sends `POST /e2e/runs` with protocol header and optional idempotency key.
3. Server validates protocol/env/suite/journeys/action-expect pairs, acquires environment lock, runs seed script, and
   queues run+journey rows.
4. Client executes journey steps and writes JSONL logs using schema `e2e_log.v1`.
5. Client submits per-journey outcomes via `POST /e2e/runs/:id/results`.
6. Server marks final run status from journey outcomes and releases lock.

Journey semantics:

- Fail-fast inside each journey.
- Continue other journeys in the same run.
- Aggregate run status from all journey results.

JSONL v1 semantics:

- `journey started` record includes run context (`run_id`, `suite_id`, `environment_label`, `trigger_source`,
  `protocol_version`).
- Exactly one terminal record per step (`status=passed|failed`) with `duration_ms`.
- `journey completed` record includes `duration_ms`, `steps_run`, `steps_passed`, `steps_failed`, and failure summary
  fields.
- Response metrics (`http_status`, `response_type`, `bytes`, `truncated`) are canonical top-level fields on step
  records.
- `action_data` stores action-specific payloads; sensitive keys are redacted before writing logs.
- `bytes` is the original response-body size before truncation.
- `truncated=true` means `action_data.body_preview` was clipped to the first 500 bytes.

### Add a New E2E Journey

1. Generate scaffold: `packages/client/scripts/e2e/scaffold --id <journey_id> --suite <suite_id> --description "<text>"
   --steps action_a:expect_a,action_b:expect_b` (preview-only: add `--dry-run`; overwrite existing files: add `--force`)
   Optional for advanced cases: `step_id=action:expect` (when the step label must differ from the action token).
2. Fill in client action handlers from the generated stub at
   `packages/client/internal/e2e/scaffold/<journey_id>.go.stub`.
3. Register action/expect tokens using generated server stub at
   `packages/server/lib/nixstasis/e2e/scaffold/<journey_id>.ex.stub`.
4. Add journey to suite mappings in `packages/client/scripts/e2e/config.example.yaml`, `packages/server/config/dev.exs`,
   and `packages/server/config/test.exs`.
5. Run E2E and verify UI/API rendering.
6. Add tests in `packages/client/internal/e2e` and `packages/server/test/nixstasis/e2e` + controller tests.

### An E2E Test by Example

Reference journey: `runtime_step_labels`

Run command:

```bash
cd packages/client
scripts/e2e/run --suite runtime_step_labels --journey step_labels --env local --trigger manual --protocol-version 1
```

Files that make up this example journey:

- `packages/client/scripts/e2e/journeys/runtime_step_labels.yaml`: Journey definition with optional `step_id` labels
  (`step_id != action`) to demonstrate cleaner dashboard labels.
- `packages/server/config/dev.exs`: Adds suite mapping `"runtime_step_labels" => ["runtime_step_labels"]` for local
  runs.
- `packages/server/config/test.exs`: Adds suite mapping `"runtime_step_labels" => ["runtime_step_labels"]` for test env
  parity.
- `packages/client/internal/e2e/journey.go`: Supports optional `step_id` in YAML and fallback behavior (`step_id`
  defaults to `action`).
- `packages/client/internal/e2e/journey_executor.go`: Emits `step_id` only when different from `action`, reducing
  redundant log fields.
- `packages/server/lib/nixstasis_web/live_dashboard/e2e_log_presenter.ex`: Prefers `step_id` over `action` in Journey
  Log display when custom labels are provided.

### Reliability + Lifecycle

- Environment lock table prevents overlapping runs in same environment.
- Retention is enforced in server app via periodic worker:
  - `retention_days` (default `14`)
  - `max_run_count` (default `2000`)
  - `max_log_bytes` (default `1_000_000_000`)
  - pruning order is oldest-first.
- Deleting a run also deletes associated log files.
- Missing/pruned logs return typed `log_unavailable` errors (HTTP `410`) so UI can show non-blocking unavailable states.

### CI + GitHub Pages

- Workflow: `.github/workflows/e2e-pages.yml`
- Runs all server-configured suites in CI by calling:
  - `packages/client/scripts/e2e/run_all_suites`
  - suite list is fetched from `GET /e2e/suites`
- Publishes static pages through:
  - `packages/server/lib/mix/tasks/e2e.export_static.ex`
- Pages output is manifest-led:
  - `runs.json` is source of truth
  - run directories live under `runs/<ref-name>/<short-sha>/`
  - root `index.html` loads `runs.json` client-side
- Retention:
  - governed by `MAX_E2E_RUNS` (fallback `200`)
  - non-release runs are pruned oldest-first
  - semver tags (`X.Y.Z` and `vX.Y.Z`) are preserved forever

### File Types and Ownership

<!-- markdownlint-disable MD013 -->
| File Type | Path Pattern | Owned By | Purpose |
| --- | --- | --- | --- |
| Journey spec YAML | `packages/client/scripts/e2e/journeys/*.yaml` | Client | Declarative journey specs (`id`, `description`, `steps`). |
| Runner entry script | `packages/client/scripts/e2e/run` | Client | Shell entrypoint for E2E CLI. |
| Runner CLI main | `packages/client/scripts/e2e/main.go` | Client | Flag parsing and run launch. |
| Runner config YAML | `packages/client/scripts/e2e/config.example.yaml` | Client | Default suite/env/protocol/journeys. |
| Runner orchestration | `packages/client/internal/e2e/runner.go` | Client | Creates run, executes journeys, submits results. |
| Journey execution + logs | `packages/client/internal/e2e/journey_executor.go` | Client | Action execution + JSONL log emission. |
| E2E API client | `packages/client/internal/e2e/api.go` | Client | Calls run creation/results endpoints and sets protocol header. |
| E2E context | `packages/server/lib/nixstasis/e2e.ex` | Server | Run lifecycle, idempotency, locking, retention, log reads. |
| Contract guards | `packages/server/lib/nixstasis/e2e/protocol.ex`, `journey_selection.ex`, `data_policy.ex`, `expectation_registry.ex` | Server | Protocol, suite/journey, env policy, and action/expect validation. |
| Locking | `packages/server/lib/nixstasis/e2e/environment_lock.ex`, `environment_locks.ex` | Server | Single active run per environment. |
| Log storage | `packages/server/lib/nixstasis/e2e/log_store.ex` | Server (reads client logs too) | Safe read/write/delete + availability semantics. |
| Retention worker | `packages/server/lib/nixstasis/e2e/retention_worker.ex` | Server | Periodic pruning by age/count/size policy. |
| HTTP controllers | `packages/server/lib/nixstasis_web/controllers/e2e_run_controller.ex`, `e2e_run_result_controller.ex` | Server | Typed API responses and error codes. |
| Dashboard page | `packages/server/lib/nixstasis_web/live_dashboard/e2e_page.ex` | Server | Runs/results/log visualization. |
| Migrations | `packages/server/priv/repo/migrations/20260209235459_create_e2e_runs.exs`, `packages/server/priv/repo/migrations/20260212163000_harden_e2e_contracts.exs` | Server | Schema for runs/results and reliability hardening fields. |
| Seed script | `packages/server/priv/e2e/seed.exs` | Server | Baseline data reset before run acceptance. |
| OpenAPI contract | `specs/008-server-client-e2e-tests/contracts/e2e-runs.openapi.yaml` | Both | Contract reference for endpoints/payloads/errors. |

## Architecture Overview

<!-- ```mermaid GitHub still doesn't support ELK layout
---
config:
  layout: elk
---
flowchart TB
 subgraph Edge["<b>Remote Access</b>"]
        User["FS Agent"]
        Browser["Browser"]
        Shell["Terminal"]
        AuthCrunch["Microsoft Entra ID"]
        Caddy["Caddy + AuthCrunch"]
  end
 subgraph Server["<b>Server Infrastructure</b>"]
        UI["Nixstasis UI"]
        API["Nixstasis API"]
        DB[("Database")]
        Alembic["Alembic Migrations"]
        FRPS["FRPS Server"]
  end
 subgraph Device["<b>AlarmBox</b>"]
        Client["Nixstasis Client"]
        WebUI["Cockpit"]
        SSH["SSH"]
        FRPC["FRP Client"]
  end
    User ==> Browser & Shell
    Browser == "|1. Authentication|" ==> AuthCrunch
    AuthCrunch == "|2. Authorize|" ==> Caddy
    Caddy == |HTTPS/WSS| ==> UI
    Caddy == |Proxy| ==> FRPS
    Shell == |SSH Access| ==> FRPS
    UI <== State/Data ==> API
    API <== Queries ==> DB
    Alembic == Migrations ==> DB
    Client == |Events/Data| ==> API
    FRPC <== Secure Tunnel ==> FRPS
    Client ==> FRPC
    WebUI ==> FRPC
    SSH ==> FRPC
    FRPS == |Web UI| ==> WebUI
    FRPS == |Terminal| ==> SSH

    style User fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style Browser fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style Shell fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style AuthCrunch fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style Caddy fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style UI fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style API fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style DB fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style Alembic fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style FRPS fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style Client fill:#E1BEE7,stroke:#4A148C,stroke-width:3px,color:#000
    style WebUI fill:#E1BEE7,stroke:#4A148C,stroke-width:3px,color:#000
    style SSH fill:#E1BEE7,stroke:#4A148C,stroke-width:3px,color:#000
    style FRPC fill:#E1BEE7,stroke:#4A148C,stroke-width:3px,color:#000
    style Edge fill:#FFE4E1,stroke:#8B0000,stroke-width:4px,color:#000
    style Server fill:#E0F2F7,stroke:#004D7A,stroke-width:4px,color:#000
    style Device fill:#F3E5F5,stroke:#4A148C,stroke-width:4px,color:#000
``` -->

## Status Snapshot (from specs task checklists)

- **Client rewrite (Go)**: Core functionality is implemented (registration, polling, FRP management, packaging). Two
  items remain in progress: `internal/plugin` foundational structs (T006) and FRP lifecycle hooks (T027).
- **Server rewrite (Elixir/Phoenix)**: Core monitoring, dashboard, and UI polish tasks are complete. The device list
  enhancement spec (005) is pending.

## FRP (Fast Reverse Proxy)

This service has two components:

- `frps`: The server, which must run on the same server as Nixstasis and must have a wildcard domain name assigned to
          the IP Address that the server is running. The IP Address must be publicly reachable on the Internet.
- `frpc`: This is the client that must be deployed on the devices that Nixstasis will monitor and provide remote access.

These services are configured using a `toml` file. See the FRP docs for configuration details.

This repo includes a fully deployable configuration for the server designed for this service. It currently supports both
`ssh` and `https` proxying. This allows Nixstasis to provide remote access to the device's Web UI (Cockpit) and to
connect to the device via a terminal using `ssh` if for some reason the Web UI becomes unreachable due to a
configuration issue.

The nixstasis client includes a configuration file as well, that uses environment variables to provide a template. When
the Nixstasis client starts the `frpc` program, it provides the required values to ensure that each device gets a unique
subdomain. The current pattern for subdomains is `atom-${MAC_ADDRESS}` where the MAC Address is lowercased with the `:`
stripped. For example `atom-8268a89d95e7`.

## Caddy Server

Caddy is the front-end server and provides these features:

- Reverse proxying to FRPS
- Automatic TLS (HTTPS) certificates per device
- Static file serving for Nixstasis's UI
- Authentication via the AuthCrunch plugin

FRPS provides the public tunnel to devices but is not used for TLS termination. FRPS also does not reliably handle HTTP
upgrade requests (required for WebSockets) and lacks built-in ACME support. Caddy handles TLS termination and ACME,
which is why it's used in front of FRPS.

For on-demand certificates, Caddy requests approval the first time a subdomain is accessed. Nixstasis exposes the
`/permit_tls` endpoint to authorize these requests. The endpoint expects a `domain` query parameter and only allows a
certificate when the domain should be exposed for remote access. If no device matches the requested domain, or if remote
access hasn't been requested, the request is denied. Requests for the `nixstasis`, `auth`, and `frp-admin` domains are
always approved because Nixstasis depends on them.

Caddy may be configured using its Caddyfile or JSON formats; the repo includes a deployable Caddyfile covering the
current features.

## AuthCrunch

`AuthCrunch` is a plugin for Caddy that provides Authentication, Authorization, and Accounting (AAA) via a highly
flexible set of configuration options it adds to Caddy. The main feature used for Nixstasis is to provide authentication
using Microsoft Entra ID. The current configuration just provides basic support for authentication. If the user is a
valid user in the tenant, the user has permission to access Nixstasis.

However, AuthCrunch provides the ability to do user transforms. It can be configured to translate Entra ID Groups into
defined groups. Out of the box, those groups are `authp/admin`, `authp/user`, and `authp/guest`. These groups can be
passed to the backend application, in this case Nixstasis's backend, to be used to modify the actions a user can take.
This is left as a future TODO.
