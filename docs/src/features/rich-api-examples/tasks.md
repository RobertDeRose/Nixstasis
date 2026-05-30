# Rich API Examples Tasks

## Tasks

- [x] T000 Confirm scope and review this feature design before implementation.
- [x] T001 Inventory maintained HTTP API surfaces under `/api/v1`, `/e2e`, `/api/json`, and retained hand-maintained OpenAPI files.
- [x] T002 Map each planned example to a current implementation, controller test, client transport test, generated OpenAPI path, or retained OpenAPI contract.
- [x] T003 Add device registration examples for pending approval and approved credential issuance where current behavior supports those states.
- [x] T004 Add heartbeat examples for normal polling, no-command responses, command delivery, deferred payload metadata, and remote-access token behavior.
- [x] T005 Add command result and deferred payload fetch examples for success, validation failure, authorization failure, and missing payload behavior.
- [x] T006 Add Caddy `check_domain` allow and deny examples using fake local and production-shaped hostnames.
- [x] T007 Add E2E API examples for run creation, idempotent reuse, environment lock conflict, protocol mismatch, seed failure, result submission, cancellation, and missing or pruned logs.
- [x] T008 Add or link builder API examples for option lookup, validation success, validation failure, stale selections, missing schemas, and authorization failures where current contracts expose those outcomes.
- [x] T009 Add report API examples for maintained hand-documented surfaces that remain outside generated Ash OpenAPI, and link alert-rule examples to generated `/api/json/alert_rules` OpenAPI.
- [x] T010 Update Reference links so readers can find generated Ash OpenAPI examples and retained bespoke examples from the same entry point.
- [x] T011 Validate examples against current tests, generated OpenAPI, and implementation references; update examples that do not match current behavior.
- [x] T012 Run `mdbook build docs` and fix navigation, link, or rendering issues.
- [x] T013 Run applicable OpenAPI validation for edited hand-maintained YAML contracts, or document why no project validation command applies. No hand-maintained OpenAPI YAML contracts were edited in the final implementation, and the generated Ash OpenAPI file was left unchanged after review.
- [x] T999 Review completed examples against goals, non-goals, constraints, and success criteria before close-out.
