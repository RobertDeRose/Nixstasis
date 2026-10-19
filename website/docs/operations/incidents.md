# Incident Response

Starting points for the most likely production incidents. In each case, contain the problem first, then recover, then
confirm everything works.

## Failed Migrations

Symptoms:

- `/app/bin/migrate` exits non-zero.
- The server starts but expected schema-backed behavior fails.
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
- Confirm nothing was changed to run migrations on startup; they should only ever run as a separate step.

## Broken TLS Approval

Symptoms:

- Caddy cannot issue or serve expected device wildcard certificates.
- `atom-<device>.<base-domain>` fails before reaching FRPS.
- Caddy logs show ask endpoint failures.

Immediate response:

1. Confirm `BASE_DOMAIN`, `PHX_HOST`, and `PORT=4000` in `.env`.
2. Confirm Caddy asks `http://nixstasis:${PORT}/api/v1/check_domain`.
3. Confirm the server is healthy behind Caddy.

Recovery:

1. Run `deploy/compose/scripts/validate_stack.sh deploy/compose/.env`.
2. Restart `nixstasis` and `caddy` after correcting env or Caddy config issues.
3. Validate one known approved device hostname and one denied hostname.

## FRPS Device Credential Exposure

Symptoms:

- A signed FRPS device credential may have been logged, copied, or exposed on a managed
  host.
- Unexpected FRPC clients appear in FRPS logs.

Immediate response:

1. Rotate `SECRET_KEY_BASE` if FRPS device authorization credentials may have been exposed.
2. Restart `nixstasis`; short-lived outstanding credentials then fail verification.
3. Review recent remote-access activity and device heartbeat state.

Recovery:

1. Re-open only required remote-access sessions.
2. Confirm each device receives a fresh credential in its next heartbeat while remote access is open, and that
   tunnels using the old credential are refused.
3. Validate terminal launch from the UI for a known approved device.

## Device Credential Compromise

Symptoms:

- A device API token or identity file is suspected compromised.
- Heartbeats or command results appear from an unexpected host.

Immediate response:

1. Revoke every remote-access lease for the device. Closing a session from the device's page closes only that page's
   lease, and another browser or provisioning lease would keep FRPS authorization valid:

   ```sh
   docker compose --env-file .env exec nixstasis /app/bin/nixstasis rpc \
     'Nixstasis.Devices.get_device!("<device-id>") |> Nixstasis.Devices.set_remote_access(false) |> IO.inspect()'
   ```

   Healthy: it prints `{:ok, ...}`.
2. Block the device. Rejecting it in the UI applies only to pending devices, so for an approved device change its state
   in the database; its heartbeats, results, and payload requests then fail with `device_not_approved`:

   ```sh
   docker compose --env-file .env exec postgres sh -c \
     'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "update devices set approval_status = '\''rejected'\'' where id = '\''<device-id>'\''"'
   ```

3. Restart FRPS to drop established tunnels. FRPS checks the credential only at login and proxy creation, so an
   established tunnel survives revocation, and a blocked device's rejected heartbeats no longer deliver tunnel
   shutdown or SSH revocation. The restart briefly drops every device's tunnel; devices with an active lease reconnect.

   ```sh
   docker compose --env-file .env restart frps
   ```

4. Confirm containment: the device's page shows remote access closed, and `docker compose --env-file .env logs frps`
   shows any reconnect from the device refused.
5. Rotate any host-local credentials you control on the device.

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
