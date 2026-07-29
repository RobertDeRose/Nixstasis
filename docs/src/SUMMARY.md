# Summary

[Introduction](README.md)

<!-- rumdl-disable MD025 -->

# Architecture

- [Architecture Overview](architecture.md)
- [Project Structure](repository-structure.md)
- [Runtime Boundaries](runtime-boundaries.md)
- [Data Flow](data-flow.md)
- [Module Reference](modules/index.md)
  - [Server Application](modules/server-application.md)
  - [Server Domain](modules/server-domain.md)
  - [Server Web](modules/server-web.md)
  - [Server Devices](modules/server-devices.md)
  - [Server Monitoring](modules/server-monitoring.md)
  - [Server Reporting](modules/server-reporting.md)
  - [Server E2E](modules/server-e2e.md)
  - [Client CLI](modules/client-cli.md)
  - [Client Transport](modules/client-transport.md)
  - [Client Identity](modules/client-identity.md)
  - [Client Starlark Runtime](modules/client-starlark-runtime.md)
  - [Client Command Handler](modules/client-command-handler.md)
  - [Client FRP Manager](modules/client-frp-manager.md)
  - [Client E2E Harness](modules/client-e2e-harness.md)
  - [Edge Caddy](modules/edge-caddy.md)
  - [Edge FRP](modules/edge-frp.md)
  - [Shared E2E Log Viewer](modules/shared-e2e-log-viewer.md)

# Development

- [Development Overview](development.md)
- [Developer Tooling](development/tooling.md)
- [Feature Lifecycle](development/feature-lifecycle.md)
- [Operational Unknowns](unknowns.md)

# Operations

- [Deployment Compose](modules/deployment-compose.md)
- [GitHub Pages Deployment](operations/github-pages.md)
- [Production Operations](operations/index.md)
  - [Backup And Restore](operations/backup-restore.md)
  - [Secret Rotation](operations/secret-rotation.md)
  - [Health Checks](operations/health-checks.md)
  - [Command Policies](operations/command-policies.md)
  - [Incident Response](operations/incidents.md)
  - [Upgrades And Rollbacks](operations/upgrades-rollbacks.md)
  - [HA And Scaling](operations/ha-scaling.md)

# Design

- [Planned Features](planned-features.md)
  <!-- BEGIN FEATURE DESIGNS -->
  - [Add Rule Modal Improvements](features/add-rule-modal-improvements/design.md)
  - [Ash API Contract Unification](features/ash-api-contract-unification/design.md)
  - [In-Memory SSH Authorized Keys](features/in-memory-ssh-authorized-keys/design.md)
  - [Schema-Driven Builder Dropdowns](features/schema-driven-builder-dropdowns/design.md)
  - [Server Stary Script Workbench](features/server-stary-script-workbench/design.md)
  <!-- END FEATURE DESIGNS -->
- [Implemented Features](features/index.md)
  <!-- BEGIN IMPLEMENTED FEATURES -->
  - [AuthCrunch Role Contract](features/authcrunch-role-contract/index.md)
  - [Compose Dev Harness](features/compose-dev-harness/index.md)
  - [Dashboard Home](features/dashboard-home/index.md)
  - [Device Detail Page](features/device-detail-page/index.md)
  - [Go Client Rewrite](features/go-client-rewrite/index.md)
  - [IoT Device Monitoring](features/iot-device-monitoring/index.md)
  - [Packaging and Deployment Migration](features/packaging-deployment-migration/index.md)
  - [Phoenix UI Polish](features/phoenix-ui-polish/index.md)
  - [Production Operations Runbooks](features/production-operations-runbooks/index.md)
  - [Report View Improvements](features/report-view-improvements/index.md)
  - [Rich API Examples](features/rich-api-examples/index.md)
  - [Self-Extracting Installer](features/self-extracting-installer/index.md)
  - [Server-Client E2E Tests](features/server-client-e2e-tests/index.md)
  - [Server Command Allowlist Management](features/server-command-allowlist-management/index.md)
  - [Server-Provided FRPS Token](features/server-provided-frps-token/index.md)
  - [Starlark Script System](features/starlark-script-system/index.md)
  <!-- END IMPLEMENTED FEATURES -->

# Reference

- [Documentation Conventions](introduction/documentation-conventions.md)
- [Project Overview](introduction/project-overview.md)
- [Tooling Reference](reference/tooling.md)
- [API & Runtime Contracts](reference/contracts.md)
  - [OpenAPI Contracts](reference/openapi/index.md)
- [Agent Workflows](reference/agent-workflows.md)
- [E2E Results](reference/e2e-results.md)
- [Client-Server Interface](client-server-interface.md)
