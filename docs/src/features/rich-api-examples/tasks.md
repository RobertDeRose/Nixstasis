# Rich API Examples Tasks

## Tasks

- [ ] T000 Confirm scope and review this feature design before implementation.
- [ ] T001 Inventory maintained HTTP API surfaces under `/api/v1`, `/e2e`, `/api/json`, and retained hand-maintained OpenAPI files.
- [ ] T002 Map each planned example to a current implementation, controller test, client transport test, generated OpenAPI path, or retained OpenAPI contract.
- [ ] T003 Add device registration examples for pending approval and approved credential issuance where current behavior supports those states.
- [ ] T004 Add heartbeat examples for normal polling, no-command responses, command delivery, deferred payload metadata, and remote-access token behavior.
- [ ] T005 Add command result and deferred payload fetch examples for success, validation failure, authorization failure, and missing payload behavior.
- [ ] T006 Add Caddy `check_domain` allow and deny examples using fake local and production-shaped hostnames.
- [ ] T007 Add E2E API examples for run creation, idempotent reuse, environment lock conflict, protocol mismatch, seed failure, result submission, cancellation, and missing or pruned logs.
- [ ] T008 Add or link builder API examples for option lookup, validation success, validation failure, stale selections, missing schemas, and authorization failures where current contracts expose those outcomes.
- [ ] T009 Add report API examples for maintained hand-documented surfaces that remain outside generated Ash OpenAPI, and link alert-rule examples to generated `/api/json/alert_rules` OpenAPI.
- [ ] T010 Update Reference links so readers can find generated Ash OpenAPI examples and retained bespoke examples from the same entry point.
- [ ] T011 Validate examples against current tests, generated OpenAPI, and implementation references; update examples that do not match current behavior.
- [ ] T012 Run `mdbook build docs` and fix navigation, link, or rendering issues.
- [ ] T013 Run applicable OpenAPI validation for edited hand-maintained YAML contracts, or document why no project validation command applies.
- [ ] T999 Review completed examples against goals, non-goals, constraints, and success criteria before close-out.
