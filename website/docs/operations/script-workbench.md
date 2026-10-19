# Stary Script Workbench

The workbench lets you write, check, test, and deploy `.stary` telemetry scripts from the web UI instead of logging in
to each device. It sits alongside the `nixstasis script` commands on the device; it does not replace the device's own
parser, runtime, or safety checks.

Open the script list at `/scripts`, and open a draft at `/scripts/:id`.

## Write, test, and deploy a script

1. Create a draft from the Scripts list.
2. Fill in the front matter and write the Starlark body.
3. Select **Validate** to check the rendered `.stary` script.
4. On the **Test** tab, search for and select the devices to test on.
5. Queue the test, then check each device's status and output.
6. Once the test passes, deploy the validated version.
7. If a run fails or only partly succeeds, retry it. You can also cancel a run that is still in progress.

The server keeps the front matter and body separately and renders them into the final script. Once a version is
created, its rendered script never changes, so editing the draft afterwards cannot alter a test or deployment that is
already queued.

## Who can target which devices

Every workbench action that changes something (writing, validating, testing, deploying, retrying, cancelling, and
archiving) needs operator permissions. In production, Caddy and AuthCrunch sign you in, and the server builds your
permissions from the verified claims.

- If you can see every device, you can target any approved device.
- If you are limited to certain devices, you can target only those. If any selected device is outside your access, or
  you select none, nothing is created.
- The device picker shows at most 50 matches per search, and remembers what you have already selected when you search
  again.
- A run can target at most 250 devices. The server enforces this when the run is queued, not just in the page.
- A script larger than 1 MiB, once encoded, is refused, because devices could not download it.
- In production, changes are refused unless the server knows who you are. Audit events name you by your sign-in
  subject, or by your email if there is no subject.

Results from devices are authenticated with each device's own token, and are credited to that device, not to the
operator who queued the run.

## What validation checks

The server's **Validate** step catches common mistakes before anything is sent to a device. It checks that:

- the front matter has the required fields and a script name;
- the schema is well formed;
- the body is not empty and has a sensible Starlark structure;
- the script renders to a valid `.stary` file.

It is not a full Starlark parser. The device does the complete job: parsing, compiling the schema, providing builtins,
enforcing allowed commands and timeouts, and checking the output. If server validation fails, nothing can be queued.
If the device rejects the script or it fails while running, that shows up as that device's result.

## How tests and deployments run

A test sends the device a `run_script` command. The device runs the script once with its normal runtime and does not
install it. A deployment sends `install_script` with the validated version, and the device applies the same checks on
front matter, version, schema, and files as for any other install.

Scripts up to 4,096 bytes travel inside the command. For a larger script, the command carries a `payload_ref`, and the
device fetches the script before running it:

```text
GET /api/v1/devices/:device_id/command_payloads/:ref
Authorization: Bearer <device-token>
```

If that payload is missing or invalid, the device reports a failure and runs or installs nothing.

## Run states

| Record        | States                                                                              |
|---------------|-------------------------------------------------------------------------------------|
| Test run      | `pending`, `running`, `passed`, `failed`, `timed_out`, `unsupported`, `unavailable` |
| Deployment    | `pending`, `running`, `deployed`, `partial`, `failed`                               |
| Device action | `queued`, `delivered`, `acknowledged`, `failed`, `missing_payload`                  |

Commands reach devices with their heartbeats, so an offline device stays pending until it checks in. Cancelling a run
marks it failed on the server, but a device that already received the command may still finish and report back.

Retrying an old run first checks how many devices it had, then reloads only devices you can still access. An old run
over the 250-device limit can still be viewed, but retrying it fails without changing anything.

## Audit trail

Every successful change, and every failed validation, writes a structured script audit event with `action`,
`actor_id`, `actor_type: :operator`, a UTC `timestamp`, and the relevant script, version, target, or result details.
Results reported by devices use `actor_type: :device` and the device's ID.

`Nixstasis.Scripts.Audit` writes each event to the Elixir `Logger` and broadcasts `{:script_audit, payload}` on the
`script_audit` PubSub topic. There is no audit table, so how long events are kept, how they are exported, and who can
read them depends on your log collection. The PubSub topic is for live notifications only.

## Troubleshooting

- **Not authorized:** check your role and, if you are limited to certain devices, that the device is one of them.
  Reload the page after your access changes.
- **No script version available:** validate the draft, and make sure the front matter has a version.
- **A test or deployment stays pending:** check the device's last heartbeat and whether the command was delivered.
  The server waits for the device to check in.
- **Missing payload:** look at the device's action and the server logs for the payload reference. The device reports
  a clear fetch failure.
- **The script fails on the device:** read that device's result. Fix the script, its schema, your assumptions about
  the device, or the device's command policy, then retry.

## Not available over the API

The six `script_*` records are internal. They are deliberately not exposed through the JSON:API, so that every change
goes through `Nixstasis.Scripts` and keeps its validation, permission checks, command delivery, and audit events.

How the workbench is built is covered in [Server Scripts](../modules/server-scripts.md), and the device command format
in [Client-Server Interface](../client-server-interface.md).
