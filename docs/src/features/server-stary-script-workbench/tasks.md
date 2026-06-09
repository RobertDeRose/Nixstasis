# Tasks: Server Stary Script Workbench

- **[P]**: Can run in parallel after dependencies for the phase are complete.
- **[Story]**: User story owning the task.
- Include exact file paths in implementation task descriptions.

## Phase 0: Scope Guard

- [X] T000 Confirm this feature remains independent from command allowlist
  management and dashboard device groups. `exec_cmd` denial should be surfaced as
  client test output, not modeled as a dependency on another feature.

## Phase 1: Discovery And Contract Design

- [X] T001 Inventory existing Stary parser, executor, install, remove, and test
  behavior in `packages/client/internal/script/` and
  `packages/client/cmd/nixstasis/`.
- [X] T002 Inventory existing server device command persistence and delivery
  behavior in `packages/server/lib/nixstasis/devices.ex`,
  `packages/server/lib/nixstasis/devices/pending_command.ex`, and
  `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex`.
- [X] T003 Decide whether server-side validation is implemented natively in
  Elixir or by a packaged/supervised validation helper, and record the decision
  in `docs/src/features/server-stary-script-workbench/design.md`.
- [X] T004 Define the test-only script execution contract between Phoenix and the
  Go client, including payload shape, timeout behavior, result envelope, and
  unsupported-client failure behavior.
- [X] T005 Define when test and deploy commands use inline payloads versus
  deferred command payloads, including payload retention and 404 behavior.
- [X] T006 Define script draft, version, validation result, test run, deployment
  run, and per-client result lifecycle states.

## Phase 2: Server Persistence And Domain

- [X] T007 Add server persistence for script drafts and script versions in
  `packages/server/priv/repo/migrations/` and
  `packages/server/lib/nixstasis/scripts/`.
- [X] T008 Add server persistence for validation results, test runs, deployment
  runs, and per-client action results in `packages/server/priv/repo/migrations/`
  and `packages/server/lib/nixstasis/scripts/`.
- [X] T009 Wire script resources or context modules into
  `packages/server/lib/nixstasis/domain.ex` or the appropriate server domain
  boundary.
- [ ] T010 Add authorization checks for script create, edit, validate, test, and
  deploy actions using the existing browser/operator permission model.
- [ ] T011 Add audit recording for script validation, test, deployment, archive,
  and failure transitions.
- [ ] T012 Run named Ash codegen for new or changed Ash resources and verify no
  `*_dev.exs` migrations or `*_dev.json` snapshots remain in the worktree.

## Phase 3: Validation

- [ ] T013 Implement canonical `.stary` rendering from structured front matter
  plus script body in the server code.
- [ ] T014 Implement server-side front-matter, Stary structure, schema, and
  Starlark parse validation.
- [ ] T015 Add validation tests that cover valid scripts, invalid YAML, missing
  script body, invalid schema, duplicate or invalid names, and Starlark syntax
  errors.
- [ ] T016 Add compatibility tests or fixtures proving server validation agrees
  with Go client parsing and schema expectations for representative scripts.

## Phase 4: Client Test-Only Execution

- [ ] T017 Add a client command handler path for executing provided Stary script
  content without installing it in `packages/client/internal/commands/`.
- [ ] T018 Return a structured test result envelope from the client with status,
  output, warnings, validation status, error type, error message, and timing data
  where available.
- [ ] T019 Add client tests for successful test-only execution, invalid script,
  schema mismatch, runtime failure, timeout, and `exec_cmd` allowlist rejection.
- [ ] T020 Ensure test-only execution does not change installed scripts or normal
  polling script discovery.

## Phase 5: Server Test And Deployment Orchestration

- [ ] T021 Implement server actions for queuing test-only script execution to one
  or more selected clients.
- [ ] T022 Implement server result ingestion for per-client test results and
  state transitions.
- [ ] T023 Implement server actions for deploying a validated script version to
  selected clients through the command flow.
- [ ] T024 Implement server result ingestion for per-client deployment
  acknowledgements and failures.
- [ ] T025 Add server tests for offline clients, duplicate command results,
  unsupported clients, partial success, retry/idempotency behavior, and
  authorization failures.
- [ ] T026 Add client/server contract tests for inline and deferred script
  payload delivery, including payload lookup failure and result acknowledgement.

## Phase 6: LiveView Workbench

- [ ] T027 Add script inventory LiveView routes and templates under
  `packages/server/lib/nixstasis_web/live/`.
- [ ] T028 Add the structured front-matter editor and Starlark body editor.
- [ ] T029 Add validation action handling and validation result display.
- [ ] T030 Add client selection for test runs and per-client test result display.
- [ ] T031 Add deployment confirmation and per-client deployment status display.
- [ ] T032 Add archive/delete or inactive-state handling for scripts that should
  leave the active inventory.
- [ ] T033 Add LiveView tests for inventory, editing, validation, client
  selection, test results, deployment, unauthorized states, and failure states.

## Phase 7: Documentation And Validation

- [ ] T034 Update internal feature design notes with final contract decisions and
  any implementation tradeoffs discovered during development.
- [ ] T035 Identify user-facing Development, Operations, Architecture, and
  Reference documentation changes needed for close-out.
- [ ] T036 Update `docs/src/reference/openapi/device-api.yaml` and
  `docs/src/client-server-interface.md` if script test/deploy command payloads
  or results become durable device API contracts.
- [ ] T037 Run `mix ash.codegen --check` if Ash resources or relationships
  changed.
- [ ] T038 Run server tests relevant to scripts, device commands, authorization,
  and LiveView behavior.
- [ ] T039 Run client tests relevant to Stary parsing, test-only execution,
  install/update behavior, and command handling.
- [ ] T040 Run `mise docs:build`.
- [ ] T999 Complete close-out by reconciling implementation, feature docs, and
  planned user-facing documentation updates.
