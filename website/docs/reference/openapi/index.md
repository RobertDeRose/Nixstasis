# OpenAPI Contracts

Nixstasis has two kinds of OpenAPI specifications: one generated from the Ash domain for `/api/json`, and three
maintained by hand for the Phoenix controller APIs. They define the request and response schemas. Rate limits, errors,
and worked examples are in [Client-Server Interface](../../client-server-interface.md).

## Generated Ash specification

The Ash JSON:API surface under `/api/json`, including the builder actions under `/api/json/builder_contract/*` and the
device runtime actions under `/api/json/device_runtime/devices`, is described by a generated specification. Phoenix
serves it at `/api/json/open_api` and Swagger UI at `/api/json/swaggerui`, and a copy is committed as
`packages/server/priv/static/openapi.yaml`. The static generator, `NixstasisWeb.AshJsonApiOpenAPISpec`, delegates to the
same router specification that serves the runtime endpoint.

Regenerate the committed copy from `packages/server`:

```bash
mise x -- mix openapi.generate
```

Check that it matches the code:

```bash
mise x -- mix openapi.spec.yaml \
  --check \
  --spec NixstasisWeb.AshJsonApiOpenAPISpec \
  --filename priv/static/openapi.yaml \
  --start-app=false
```

The Stary workbench resources are internal and are not part of `/api/json` or this specification.

## Controller API specifications

These specifications cover the routes served by Phoenix controllers. Each renders as operation pages under OpenAPI
Contracts in the site navigation, generated at build time; the links below download the source YAML.

- [Device API](device-api.yaml): registration, heartbeat, command results, deferred command payloads, device list
  filtering, TLS domain approval, AtomixOS bootstrap provisioning, and the `ssh_authorize` and `ssh_revoke` command
  payloads delivered by heartbeat. The client uses these `/api/v1` routes.
- [Report API](report-api.yaml): custom report result rows.
- [E2E API](e2e-api.yaml): runs, results, logs, and cancellation for the end-to-end test harness. Its pages are in the
  Development guide, under [E2E API](../../development/e2e/api.md), since only the test harness uses it.

## Maintaining the specifications

- Change a controller specification in the same change as its controller, and keep it consistent with
  [Client-Server Interface](../../client-server-interface.md).
- Describe a route in a controller specification only when a controller owns it; Ash-backed routes belong to the
  generated specification.
- After changing Ash resources or actions, regenerate the committed specification and run the check above.
