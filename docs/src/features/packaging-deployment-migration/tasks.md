# Tasks: Packaging And Deployment Migration

**Input**: Feature design and current deployment/package docs.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the feature scaffolding, release directories, and baseline docs needed by all stories.

- [X] T001 Create the Compose deployment directory structure in `deploy/compose/`, `deploy/compose/caddy/`, and `deploy/compose/frps/`
- [X] T002 Create the client release scaffolding for GoReleaser in `packages/client/.goreleaser.yaml` and `packages/client/scripts/release/`
- [X] T003 P Create the server container build scaffolding in `packages/server/Dockerfile`, `packages/server/.dockerignore`, and `packages/server/bin/`
- [X] T004 P Create the Caddy container build scaffolding in `packages/caddy/Dockerfile` and update helper scripts under `packages/caddy/bin/`
- [X] T005 P Add initial workflow files for image and client release delivery in `.github/workflows/build_server_image.yml`, `.github/workflows/build_caddy_image.yml`, and `.github/workflows/release_client.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define the shared runtime contract, artifact pinning rules, and test harnesses that block all user stories.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T006 Define canonical runtime configuration values in `packages/server/config/runtime.exs` for `PORT`, `PHX_HOST`, `DATABASE_URL`, and related deployment inputs
- [X] T007 P Normalize the TLS approval route and domain-rule implementation in `packages/server/lib/nixstasis_web/router.ex` and `packages/server/lib/nixstasis_web/controllers/tls_controller.ex`
- [X] T008 P Add server-side BDD coverage for runtime-contract and TLS approval behavior in `packages/server/test/nixstasis_web/controllers/` and `packages/server/test/nixstasis/`
- [X] T009 Define shared pinned artifact policy and provenance notes in `deploy/compose/README.md` and `packages/client/scripts/release/README.md`
- [X] T010 P Add shared validation helpers for bundled `frpc` path resolution and renamed config roots in `packages/client/internal/config/` and `packages/client/internal/frp/`
- [X] T011 P Add or update workflow guard logic for new image/client release paths in `.github/workflows/_check_configs.yml`

**Nixstasis**: Foundation ready - user story implementation can now begin in parallel.

---

## Phase 3: User Story 1 - Deploy the server with one documented path (Priority: P1) 🎯 MVP

**Goal**: Deliver one supported Compose-based server deployment path with explicit migrations, required ingress/authentication, and bundled/external database support.

**Independent Test**: Follow `deploy/compose/README.md` on a clean host, run `docker compose ... --profile bundled-db up -d --build`, run `bin/migrate`, and confirm `caddy`, `nixstasis`, `frps`, and profiled `postgres` behave according to the documented contract without relying on legacy server package instructions.

### Tests for User Story 1 ⚠️

- [X] T012 P US1 Add deployment smoke validation for the Compose stack in `deploy/compose/scripts/validate_stack.sh`
- [X] T013 P US1 Add ExUnit coverage for explicit migration entrypoints and runtime port expectations in `packages/server/test/nixstasis/releases/` and `packages/server/test/nixstasis_web/`

### Implementation for User Story 1

- [X] T014 P US1 Implement the Compose stack definition in `deploy/compose/docker-compose.yml`
- [X] T015 P US1 Add the operator runtime template in `deploy/compose/.env.example`
- [X] T016 P US1 Create the Compose Caddy configuration in `deploy/compose/caddy/Caddyfile`
- [X] T017 P US1 Create the Compose FRPS configuration in `deploy/compose/frps/frps.toml`
- [X] T018 US1 Write first-run and operations guidance in `deploy/compose/README.md`
- [X] T019 US1 Implement the multi-stage Phoenix release image in `packages/server/Dockerfile` and supporting scripts in `packages/server/bin/`
- [X] T020 US1 Implement the AuthCrunch-enabled Caddy image build in `packages/caddy/Dockerfile` and `packages/caddy/bin/build_caddy.sh`
- [X] T021 US1 Update server release operations and runtime assumptions in `packages/server/README.md`
- [X] T022 US1 Remove abandoned server package assets and stop presenting them as the supported path in `README.md`, `packages/server/package_options.yml`, and `packages/server/build/pre_package.sh`

**Nixstasis**: User Story 1 should produce a fully documented, independently runnable Compose deployment path.

---

## Phase 4: User Story 2 - Install the client as a native package with bundled tunnel support (Priority: P1)

**Goal**: Keep the client host-native while moving release generation to GoReleaser and bundling `frpc` at the canonical private runtime path.

**Independent Test**: Run a snapshot GoReleaser build, install the generated package on a supported Linux host, and verify the `nixstasis` command, config templates, service assets, and `/usr/libexec/nixstasis/frpc` are installed and usable without a separate FRP package.

### Tests for User Story 2 ⚠️

- [X] T023 P US2 Add Go unit tests for bundled `frpc` path resolution and config-root defaults in `packages/client/internal/config/config_test.go` and `packages/client/internal/frp/manager_test.go`
- [X] T024 P US2 Add release artifact verification for package contents in `packages/client/build/bin/verify_artifacts.sh`

### Implementation for User Story 2

- [X] T025 P US2 Implement the GoReleaser configuration in `packages/client/.goreleaser.yaml`
- [X] T026 P US2 Add pinned `frpc` fetch and staging scripts in `packages/client/build/bin/` and `packages/client/build/`
- [X] T027 US2 Rename the client command and packaging metadata in `packages/client/cmd/nixstasis/` and `packages/client/Makefile`, removing the abandoned `package_options.yml` path
- [X] T028 US2 Update client runtime defaults to `nixstasis` paths in `packages/client/internal/config/config.go`, `packages/client/internal/frp/manager.go`, and `packages/client/internal/script/discovery.go`
- [X] T029 US2 Update polling and registration flows to use bundled `frpc` and renamed config paths in `packages/client/cmd/nixstasis/poll.go` and `packages/client/cmd/nixstasis/register.go`
- [X] T030 US2 Remove abandoned package install-time assumptions in `packages/client/bin/pre_package.sh` and `packages/client/build/root-dir/**` with GoReleaser-managed layouts
- [X] T031 US2 Update client installation and release documentation in `packages/client/README.md` and `README.md`

**Nixstasis**: User Story 2 should yield native client artifacts that install and run independently of legacy FRP packaging.

---

## Phase 5: User Story 3 - Use the new Nixstasis product identity consistently (Priority: P2)

**Goal**: Remove legacy naming from all assets touched by this feature and present `Nixstasis` consistently across release, runtime, and deployment surfaces.

**Independent Test**: Review all changed deployment assets, package metadata, binaries, service files, paths, and docs touched by this feature and confirm they present `Nixstasis` with no remaining legacy naming.

### Tests for User Story 3 ⚠️

### Implementation for User Story 3

- [X] T034 P US3 Rename server-facing identifiers, including code namespaces where required, in `packages/server/mix.exs`, `packages/server/config/`, and `packages/server/lib/`
- [X] T035 P US3 Rename Caddy and FRP deployment identifiers in `packages/caddy/`, `packages/frp/`, and `deploy/compose/`
- [X] T036 P US3 Rename client-facing config, service, package, and code identifiers where required in `packages/client/build/root-dir/`, `packages/client/scripts/`, `packages/client/cmd/`, and `packages/client/internal/`
- [X] T037 US3 Update repo-level product naming and migration messaging in `README.md`, `package.md`, and deployment docs.

**Nixstasis**: User Story 3 should leave all feature-scoped assets consistently branded as `Nixstasis`.

---

## Phase 6: User Story 4 - Operate against a clear runtime contract (Priority: P2)

**Goal**: Make the runtime contract complete, operator-facing, and internally consistent across server config, Compose assets, Caddy, FRPS, and workflows.

**Independent Test**: Compare the runtime contract docs, `.env.example`, server runtime config, and deployment configs and confirm every operator-supplied setting is defined once, with no conflicting paths, ports, or domain rules.

### Tests for User Story 4 ⚠️

- [X] T038 P US4 Add server tests for domain normalization and approval matching in `packages/server/test/nixstasis/devices/approval_test.exs` and related files
- [X] T039 P US4 Add contract validation for compose/runtime docs alignment in `deploy/compose/scripts/check_runtime_contract.sh`

### Implementation for User Story 4

- [X] T040 P US4 Align Compose runtime inputs with the canonical contract in `deploy/compose/.env.example`, `deploy/compose/caddy/Caddyfile`, and `deploy/compose/frps/frps.toml`
- [X] T041 P US4 Align server runtime and endpoint documentation with the canonical contract in `packages/server/config/runtime.exs` and `packages/server/README.md`
- [X] T042 P US4 Align client-facing remote-access host and config examples in `packages/client/README.md` and `packages/client/build/root-dir/**`
- [X] T043 US4 Document external database mode and explicit migration operations in `deploy/compose/README.md` and deployment docs.
- [X] T044 US4 Update workflow inputs and release documentation to reference the canonical runtime contract in `.github/workflows/build_server_image.yml`, `.github/workflows/build_caddy_image.yml`, and `.github/workflows/release_client.yml`

**Nixstasis**: User Story 4 should leave the runtime contract complete, testable, and consistent across all touched assets.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Finish workflow migration, retire legacy release surfaces, and run end-to-end validation.

- [X] T045 P Remove abandoned package publication logic in `.github/workflows/build_package.yml` and `.github/workflows/publish_package.yml`
- [X] T046 P Implement OCI image publication logic in `.github/workflows/build_server_image.yml` and `.github/workflows/build_caddy_image.yml`
- [X] T047 P Implement client snapshot/release publication logic in `.github/workflows/release_client.yml`
- [X] T048 Add final operator validation notes and release-readiness checklist updates in deployment docs.
- [X] T049 Record operator deployment trial results for SC-002.
- [X] T050 Record client installation trial results for SC-003.
- [X] T051 Run the full validation flow and record the results.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion - blocks all user stories.
- **User Stories (Phases 3-6)**: Depend on Foundational completion.
- **Polish (Phase 7)**: Depends on completion of the desired user stories.

### User Story Dependencies

- **User Story 1 (P1)**: Starts after Phase 2 and is the MVP.
- **User Story 2 (P1)**: Starts after Phase 2 and can proceed in parallel with US1.
- **User Story 3 (P2)**: Starts after Phase 2 but should land alongside or immediately after US1/US2 to avoid mixed naming.
- **User Story 4 (P2)**: Starts after Phase 2 and integrates with US1 and US2 contract surfaces while remaining independently testable.

### Within Each User Story

- Tests should be added before or alongside implementation and must fail until the corresponding behavior exists.
- Contracts/config definitions should land before release automation that depends on them.
- Rename work must not leave contradictory `Nixstasis`/`Nixstasis` references in the same touched flow.

### Parallel Opportunities

- T003, T004, and T005 can run in parallel after setup begins.
- T007, T008, T010, and T011 can run in parallel once foundational contract direction is set.
- US1 tasks T014-T017 can run in parallel because they target separate deployment files.
- US2 tasks T025-T026 and T027-T030 have substantial parallelism across distinct client files.
- US3 rename tasks T034-T036 can run in parallel across server, infra, and client surfaces.
- US4 alignment tasks T040-T042 can run in parallel across Compose, server docs/config, and client examples.
- Polish tasks T045-T047 can run in parallel across separate workflow files.

---

## Parallel Example: User Story 1

```bash
# Compose deployment artifacts
Task: "Implement the Compose stack definition in deploy/compose/docker-compose.yml"
Task: "Add the operator runtime template in deploy/compose/.env.example"
Task: "Create the Compose Caddy configuration in deploy/compose/caddy/Caddyfile"
Task: "Create the Compose FRPS configuration in deploy/compose/frps/frps.toml"
```

## Parallel Example: User Story 2

```bash
# Client release scaffolding
Task: "Implement the GoReleaser configuration in packages/client/.goreleaser.yaml"
Task: "Add pinned frpc fetch and staging scripts in packages/client/build/bin/ and packages/client/build/"

# Client runtime path updates
Task: "Update client runtime defaults to nixstasis paths in packages/client/internal/config/config.go, packages/client/internal/frp/manager.go, and packages/client/internal/script/discovery.go"
Task: "Update polling and registration flows to use bundled frpc and renamed config paths in packages/client/cmd/nixstasis/poll.go and packages/client/cmd/nixstasis/register.go"
Task: "Replace abandoned package install-time assumptions in packages/client/bin/pre_package.sh and packages/client/build/root-dir/** with GoReleaser-managed layouts"
```

## Parallel Example: User Story 3

```bash
# Rename workstreams
Task: "Rename server-facing identifiers, including code namespaces where required, in packages/server/mix.exs, packages/server/config/, and packages/server/lib/"
Task: "Rename Caddy and FRP deployment identifiers in packages/caddy/, packages/frp/, and deploy/compose/"
Task: "Rename client-facing config, service, package, and code identifiers where required in packages/client/build/root-dir/, packages/client/scripts/, packages/client/cmd/, and packages/client/internal/"
```

## Parallel Example: User Story 4

```bash
# Runtime contract alignment
Task: "Align Compose runtime inputs with the canonical contract in deploy/compose/.env.example, deploy/compose/caddy/Caddyfile, and deploy/compose/frps/frps.toml"
Task: "Align server runtime and endpoint documentation with the canonical contract in packages/server/config/runtime.exs and packages/server/README.md"
Task: "Align client-facing remote-access host and config examples in packages/client/README.md and packages/client/build/root-dir/**"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational.
3. Complete Phase 3: User Story 1.
4. Validate the Compose deployment path independently using the quickstart flow.

### Incremental Delivery

1. Deliver US1 to establish the supported server deployment path.
2. Deliver US2 to restore client-native release capability without external FRP packaging.
3. Deliver US3 to complete the product rename across all touched assets.
4. Deliver US4 to finalize the runtime contract and eliminate deployment ambiguity.
5. Finish with workflow migration and full release validation in Phase 7.

### Parallel Team Strategy

1. One engineer owns foundational runtime contract normalization.
2. After Phase 2, split work by deliverable boundary:
   - Engineer A: Compose/server image work (US1)
   - Engineer B: client packaging/runtime work (US2)
   - Engineer C: naming and contract consistency work (US3/US4)
3. Rejoin for workflow migration and final validation.

---

## Notes

- Every task follows the required checklist format with task ID, optional `[P]`, story label where required, and explicit file paths.
- Tests are included because the feature plan explicitly requires them.
- User stories remain independently testable even where they touch shared assets.
- The suggested MVP scope is **User Story 1**.
