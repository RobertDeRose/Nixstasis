# Production Operations Runbooks Tasks

## Tasks

- [x] T000 Confirm scope and review the feature design before implementation.
- [x] T001 Inventory existing production deployment docs, Compose files, and runtime contract scripts that the runbooks should reference.
- [x] T002 Create the production operations mdBook section under `docs/src/operations/` and update `docs/src/SUMMARY.md` navigation.
- [x] T003 Draft backup and restore procedures for bundled PostgreSQL and external PostgreSQL modes.
- [x] T004 Draft secret rotation procedures for Phoenix, AuthCrunch/OIDC, AuthCrunch role/group inputs, JWT material, FRPS auth/dashboard credentials, and database credentials.
- [x] T005 Draft operational health checks for Phoenix, Caddy, FRPS, PostgreSQL, device freshness, E2E retention, remote access, runtime contract drift, and Compose render validity.
- [x] T006 Draft incident-response playbooks for failed migrations, TLS approval failures, FRPS token exposure, device credential compromise, and E2E retention/log failures.
- [x] T007 Draft upgrade and rollback validation guidance for Compose services and client release artifacts.
- [x] T008 Document explicit HA and scaling boundaries for the supported Compose deployment.
- [x] T009 Update cross-links from deployment and runtime-boundary docs to the production operations runbooks.
- [x] T010 Validate docs with `mdbook build docs` and fix navigation or link issues.
- [x] T011 Run or document applicability of `deploy/compose/scripts/check_runtime_contract.sh` and `deploy/compose/scripts/validate_stack.sh` for the final runbook changes.
- [x] T999 Review the completed runbooks against the design goals, constraints, non-goals, and success criteria.
