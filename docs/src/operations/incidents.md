# Incident Response

These playbooks are starting points for production incidents. Prefer containment
first, then recovery, then validation.

## Failed Migrations

Symptoms:

- `/app/bin/migrate` exits non-zero.
- Phoenix starts but expected schema-backed behavior fails.
- PostgreSQL logs show migration conflicts or permission errors.

Immediate response:

1. Stop deploying new image refs.
2. Preserve current logs and migration output.
3. Take a database backup if the database is still reachable.
4. Confirm the running image digest and `.env` values.

Recovery:

1. Restore the last known-good database backup to a disposable stack if needed.
2. Re-run `/app/bin/migrate` only after identifying the failed migration step.
3. Roll back to the previous digest-pinned image if the new image cannot migrate
   safely.

Validation:

- Run the checks in [Health Checks](health-checks.md).
- Confirm migrations are explicit and were not hidden in app startup.

## Broken TLS Approval

Symptoms:

- Caddy cannot issue or serve expected device wildcard certificates.
- `atom-<device>.<base-domain>` fails before reaching FRPS.
- Caddy logs show ask endpoint failures.

Immediate response:

1. Confirm `BASE_DOMAIN`, `PHX_HOST`, and `PORT=4000` in `.env`.
2. Confirm Caddy asks `http://nixstasis:${PORT}/api/v1/check_domain`.
3. Confirm Phoenix is healthy behind Caddy.

Recovery:

1. Run `deploy/compose/scripts/validate_stack.sh deploy/compose/.env`.
2. Restart `nixstasis` and `caddy` after correcting env or Caddy config issues.
3. Validate one known approved device hostname and one denied hostname.

## FRPS Token Exposure

Symptoms:

- The shared FRPS token may have been logged, copied, or exposed on a managed
  host.
- Unexpected FRPC clients appear in FRPS logs.

Immediate response:

1. Rotate `FRPS_AUTH_TOKEN` in `.env`.
2. Restart `frps` and `nixstasis`.
3. Review recent remote-access activity and device heartbeat state.

Recovery:

1. Re-open only required remote-access sessions.
2. Confirm managed clients reconnect only when the server returns the new token
   during requested remote access.
3. Validate terminal launch from the UI for a known approved device.

## Device Credential Compromise

Symptoms:

- A device API token or identity file is suspected compromised.
- Heartbeats or command results appear from an unexpected host.

Immediate response:

1. Disable or reject the affected device from the operator UI or database-backed
   device state.
2. Rotate any host-local credentials controlled by the operator.
3. Stop active remote-access sessions for the device.

Recovery:

1. Re-register or reprovision the device with a fresh identity.
2. Confirm old credentials no longer authenticate.
3. Confirm the replacement device resumes heartbeat and command polling.

## E2E Retention Or Log Failures

Symptoms:

- Retention worker logs repeated prune failures.
- E2E result pages reference missing logs.
- E2E storage grows unexpectedly.

Immediate response:

1. Preserve affected logs and run metadata.
2. Confirm whether E2E is intentionally enabled in this environment.
3. Check disk usage where E2E logs and reports are stored.

Recovery:

1. Correct filesystem permissions or storage limits.
2. Re-run retention only after confirming the retention policy and backup needs.
3. Validate retained E2E pages and log links.
