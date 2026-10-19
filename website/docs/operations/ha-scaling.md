# HA And Scaling

The supported deployment is one Compose stack. It is built to be easy to understand and recover, and it suits small
production installations, but it is not highly available.

## What is supported

- One server (the `nixstasis` service) behind Caddy.
- One Caddy service for public HTTPS, AuthCrunch, and TLS.
- One FRPS service for device tunnels.
- The bundled PostgreSQL, or an external PostgreSQL database you manage.
- Backups, restores, secret rotation, and upgrades to digest-pinned images, all run by hand.

## What is not provided

- Clustering the server across several nodes.
- Automatic failover for Caddy or FRPS.
- High availability for the bundled `postgres` service.
- Migrations without downtime.
- Automatic rollback after a failed migration or upgrade.
- Spreading browser terminal sessions across several server nodes.

## External PostgreSQL

You can point `DATABASE_URL` at an external, managed PostgreSQL service. Its availability, backups, maintenance
windows, and point-in-time recovery are then the job of that platform. You still need to run the
[Health Checks](health-checks.md) after changes.

## Scaling

Don't run more than one copy of any Compose service. Remote access relies on the server, FRPS, Caddy, and the device
client working together as a single stack, and running extra copies breaks that.

## Staying available

Without automatic failover, availability comes from good habits:

- Keep backups, and test restoring them.
- Keep the previous digest-pinned image references to hand.
- Validate `.env` and the rendered Compose file before every change.
- When a change fails, follow [Incident Response](incidents.md) and [Upgrades And Rollbacks](upgrades-rollbacks.md).
