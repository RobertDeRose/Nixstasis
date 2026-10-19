# Module Reference

How each part of the code works. Every page follows the same layout: what the module is responsible for (**Owns**),
how other code reaches it (**Entry points**), and the rules it enforces and depends on (**Boundaries**). The pages link
to source files rather than listing every function, so check the code for the finer details.

To run the system, see [Operations](../operations/index.md). For exact settings and API contracts, see the Reference
section. The end-to-end test system is covered under [E2E Testing](../development/e2e/server.md).

## Server

| Module                                        | Responsibility                                                                         |
|-----------------------------------------------|----------------------------------------------------------------------------------------|
| [Server Application](server-application.md)   | The OTP supervision tree and configuration.                                            |
| [Server Domain](server-domain.md)             | Ash resources, data-layer authorization, and the generated JSON:API.                   |
| [Server Web](server-web.md)                   | Routing, request pipelines, operator permissions, LiveViews, and the terminal channel. |
| [Server Devices](server-devices.md)           | Device identity, registration, groups, the command queue, and remote-access leases.    |
| [Server Provisioning](server-provisioning.md) | AtomixOS bootstrap delivery.                                                           |
| [Server Monitoring](server-monitoring.md)     | Heartbeats, telemetry, alerts, offline detection, and notifications.                   |
| [Server Scripts](server-scripts.md)           | The Stary script workbench.                                                            |
| [Server Reporting](server-reporting.md)       | Custom telemetry reports.                                                              |

## Client

| Module                                                | Responsibility                                          |
|-------------------------------------------------------|---------------------------------------------------------|
| [Client CLI](client-cli.md)                           | The `nixstasis` command tree and configuration loading. |
| [Client Transport](client-transport.md)               | HTTP calls to the server and the connection policy.     |
| [Client Identity](client-identity.md)                 | Device identity detection and credential storage.       |
| [Client Starlark Runtime](client-starlark-runtime.md) | Stary script parsing, execution limits, and builtins.   |
| [Client Command Handler](client-command-handler.md)   | Running server commands and the command policy.         |
| [Client FRP Manager](client-frp-manager.md)           | Starting `frpc` and the client-owned route profiles.    |

## Gateway

| Module                            | Responsibility                                                    |
|-----------------------------------|-------------------------------------------------------------------|
| [Gateway Caddy](gateway-caddy.md) | Public HTTPS, on-demand TLS, AuthCrunch, and gateway trust rules. |
| [Gateway FRP](gateway-frp.md)     | The FRPS tunnel server and device tunnel authorization.           |
