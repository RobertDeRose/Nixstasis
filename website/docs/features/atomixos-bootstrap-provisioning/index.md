# AtomixOS Bootstrap Provisioning

An operator can give a freshly installed, approved, online AtomixOS device its complete first configuration: a
`config.toml` or an approved config bundle. The server opens the device's own `atomixos-bootstrap` FRP route, posts the
file unchanged to AtomixOS's `/api/config`, follows the resulting job, records the outcome, and then closes the route.

The server never writes to the device's filesystem, unpacks archives, uses the browser-only `/apply` flow, or resends an
upload that AtomixOS has accepted. The original plan is in the [design record](design.md).

## What changed for users

- Upload the file with `POST /api/v1/provisioning/devices/:device_id`, as raw `application/octet-stream` bytes.
- Check progress and diagnostics with `GET /api/v1/provisioning/deliveries/:id`.
- Release a route that was kept open after an unclear outcome with `POST /api/v1/provisioning/deliveries/:id/withdraw`.
- When something is wrong (no permission, a device that is unapproved or offline, an invalid file, a missing route, a
  failure, an expired lease, or an unknown outcome) the delivery stops, and nothing is quietly uploaded twice.

## How it fits in

Provisioning reuses what already exists: device permissions, the online check, remote-access leases, Caddy's wildcard
routing, the device's versioned FRP profiles, and the usual Logger and PubSub audit events. The server only picks the
`atomixos-bootstrap` profile by name; the device decides where it points, how it serves HTTP, and the fixed `Host`
rewrite.

## Running it

- Files can be up to 32 MiB, and are tracked by their lowercase SHA-256.
- Every response from AtomixOS is capped at 1 MiB while it is read, before decoding or saving.
- The server follows a job for up to five minutes by default, and each request times out after 30 seconds.
- Only an HTTP `409` on upload is retried, at most twice.
- An unclear upload becomes `indeterminate`, and keeps its route open until you withdraw it or the lease expires.
- `ATOMIXOS_PROVISIONING_BASE_URL` overrides the per-device address, which is otherwise built from `BASE_DOMAIN`.

## Differences from the design

- **Deliveries are stored.** Each delivery is saved, so operators can see its status, and the latest job events and
  result are kept. That is because AtomixOS reports progress through its job resource, not through a second Nixstasis
  command.
- **Each delivery owns its lease.** A delivery's route lease belongs to its UUID and is saved. Withdrawing, or resuming
  after a restart, uses that same lease, never a new one with a fresh expiry. Finishing or withdrawing a delivery voids
  its credential, regardless of other operators' leases. While a delivery runs, its profile takes priority; afterwards,
  other leases get their own profiles and expiries back.

## Not included

- The design's broader 90-second usability target was not measured.
- Re-applying configuration after the first boot is not part of this action.
- There is no direct file writer, archive extractor, browser `/apply` endpoint, route definition from the client,
  arbitrary `Host` rewrite, automatic re-upload, or following of forwarding URLs.

## Tests

- `packages/server/test/nixstasis/provisioning/artifact_test.exs`: file size limits and SHA-256 tracking.
- `packages/server/test/nixstasis/provisioning_test.exs`: permission and approval checks, upload, job polling, success,
  `409` retries, unclear uploads, lease expiry, resolving `indeterminate` deliveries, and withdrawal.
- `packages/server/test/nixstasis/provisioning/http_client_test.exs`: the 1 MiB response cap, before JSON decoding.
- `packages/server/test/nixstasis/devices/remote_access_leases_test.exs`: saved, provisioning-owned route leases.
- `packages/server/test/nixstasis_web/controllers/provisioning_controller_test.exs`: the provisioning HTTP API.
- `mix ash.codegen --check`: the delivery resource and its migration.

## Related pages

- [Server Provisioning](../../modules/server-provisioning.md)
- [Client-Server Interface](../../client-server-interface.md)
- [Device API OpenAPI](../../reference/openapi/device-api.yaml)
- [Gateway FRP](../../modules/gateway-frp.md)
- [Server Devices](../../modules/server-devices.md)
- [API & Runtime Contracts](../../reference/contracts.md)
- [Deployment](../../operations/deployment.md)
