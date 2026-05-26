# HA And Scaling

The supported `deploy/compose` deployment is a single-stack Compose deployment.
It is designed to be understandable, recoverable, and suitable for small
production installations, but it does not implement high availability.

## What Is Supported

- One Phoenix `nixstasis` service behind Caddy.
- One Caddy service for public HTTP(S), AuthCrunch, and TLS termination.
- One FRPS service for managed-device tunnel ingress.
- Bundled PostgreSQL or an operator-managed external PostgreSQL database.
- Explicit backups, restores, secret rotation, and digest-pinned upgrades.

## What Is Not Guaranteed

- Multi-node Phoenix clustering.
- Automatic failover for Caddy or FRPS.
- HA PostgreSQL when using the bundled Compose `postgres` service.
- Zero-downtime migrations.
- Automatic rollback after failed migrations or image upgrades.
- Horizontal scaling of remote-access terminal sessions across multiple server
  nodes.

## External PostgreSQL

Operators may point `DATABASE_URL` at an external managed PostgreSQL service. In
that mode, database HA, backups, maintenance windows, and point-in-time recovery
belong to the external database platform. Nixstasis validation still requires the
application health checks in these runbooks.

## Scaling Guidance

Do not scale Compose services horizontally unless a future feature explicitly
documents and tests that topology. In particular, remote access depends on
coordinated Phoenix, FRPS, Caddy, and device-client behavior that this deployment
documents as a single-stack runtime boundary.

## Recovery Expectations

Availability for this deployment comes from operational discipline rather than
automatic HA:

- Keep tested database backups.
- Keep previous digest-pinned image refs available.
- Validate `.env` and Compose rendering before changes.
- Use the incident-response and rollback runbooks when a change fails.
