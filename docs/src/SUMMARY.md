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
- [Compose Dev Harness](features/compose-dev-harness/design.md)
- [Operational Unknowns](unknowns.md)

# Operations

- [Deployment Compose](modules/deployment-compose.md)
- [Server-Client E2E Tests](features/server-client-e2e-tests/design.md)
- [Self-Extracting Installer](features/self-extracting-installer/design.md)
- [Packaging And Deployment Migration](features/packaging-deployment-migration/design.md)

# Design

- [Specifications](features/index.md)
  - [IoT Device Monitoring](features/iot-device-monitoring/design.md)
  - [Dashboard Home](features/dashboard-home/design.md)
  - [Phoenix UI Polish](features/phoenix-ui-polish/design.md)
  - [Go Client Rewrite](features/go-client-rewrite/design.md)
  - [Starlark Script System](features/starlark-script-system/design.md)
  - [Schema-Driven Builder Dropdowns](features/schema-driven-builder-dropdowns/design.md)
  - [Report View Improvements](features/report-view-improvements/design.md)
  - [Add Rule Modal Improvements](features/add-rule-modal-improvements/design.md)
  - [Device Detail Page](features/device-detail-page/design.md)
  - [Server-Provided FRPS Token](features/server-provided-frps-token/design.md)
- [Planned Features](planned-features.md)

# Reference

- [API & Runtime Contracts](reference/contracts.md)
  - [OpenAPI Contracts](reference/openapi/index.md)
- [Task Reference](reference/tasks.md)
- [Agent Workflows](reference/agent-workflows.md)
- [E2E Results](reference/e2e-results.md)
- [Client-Server Interface](client-server-interface.md)
