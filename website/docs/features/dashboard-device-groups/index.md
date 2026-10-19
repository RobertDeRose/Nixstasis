# Dashboard Device Groups

Operators can organize devices into groups from the Devices view. A device can be in any number of groups, and a group
can hold any number of devices. Groups are only for organizing: they never change a device's identity or how it
behaves. The original plan is in the [design record](design.md).

## What changed for users

- **Managing groups.** Device managers with access to every device can create, edit, archive, restore, and permanently
  delete groups. Only archived, empty groups can be deleted permanently; archiving and restoring keep all memberships.
  Names are unique, ignoring case, across active and archived groups.
- **Changing membership.** Managers add or remove the devices they have selected, using the existing bulk actions.
  Adding a device that is already in a group, or removing one that is not, does nothing, and a change to several
  devices either all happens or none of it does.
- **Seeing groups.** Operators limited to some devices see only groups that contain one of their devices, and counts
  include only their devices. View-only operators cannot change anything.
- **Filtering.** The `group_id` URL parameter works together with the product, account number, IPv4 address, approval,
  connectivity, search, and sort settings, and the filter chip shows the group's name. A group that is invalid,
  archived, deleted, or out of reach gives the same "unavailable" message, so nothing leaks. Wide screens show a short
  membership summary on each row, always in the same order; small screens hide that column so the main list stays
  usable.

How to use groups day to day is covered in [Device Groups](../../operations/device-groups.md).

## How it fits in

Groups live in `Nixstasis.Devices`, on top of Ash and PostgreSQL. `DeviceGroup` and `DeviceGroupMembership` extend
the existing device data instead of adding a new service or API. The browser session's verified permissions build a
`GroupAuthorization`, and the server checks it again on every read and change.

A successful change writes a structured audit event, and separately tells the LiveView to refresh, without sending any
details in that notification. Registration, approval, heartbeats, remote access, command delivery, and API tokens did
not change.

## Running it

Deploying runs a named Ash migration that creates the empty group and membership tables. No data needs filling in, and
no client upgrade is needed. Before anyone creates groups, rolling back can drop the new empty tables. After that,
prefer fixing forward, or export the group tables and restore them, rather than a rollback that would lose data.

Audit events go to your logs, and are kept as long as your log retention allows; there is no audit table.

## Differences from the design

- Groups are managed in a panel inside the Devices view, with a built-in confirmation area, instead of a separate page
  or a new kind of dialog.
- Small screens hide the membership summary column, and show the detailed counts in the group panel instead.

## Not included

- Groups are manual and flat: no rules that fill groups automatically, and no groups inside groups.
- Groups carry no roles or permissions of their own.
- There is no public API for groups, and no group-specific telemetry.
- The audit history is kept in logs, not in the database.
- Membership is never guessed, and a group the operator cannot see is never revealed.
- Devices are unaware of groups.
- Permanent deletion is not the normal way to remove a group; archiving is.

## Tests

- `packages/server/test/nixstasis/device_groups_test.exs`: the group lifecycle, unique names, memberships, and audit
  events.
- `packages/server/test/nixstasis/devices_test.exs`: group filters combined with permissions and the other device
  filters.
- `packages/server/test/nixstasis_web/permissions_test.exs`: building group permissions from the browser session.
- `packages/server/test/nixstasis_web/live/device_live_test.exs`: managing groups and memberships, URL filtering, and
  membership summaries in the Devices view.
- `mix ash.codegen --check`, `mix format --check-formatted`, and `mix credo --strict`.
- Manual browser checks: keyboard use, the membership summaries on wide screens, URL state surviving navigation, and a
  usable 390-by-844 layout without the summary column.

## Related pages

- [Device Groups](../../operations/device-groups.md)
- [Server Devices](../../modules/server-devices.md)
- [Architecture Overview](../../architecture.md)
- [Introduction](../../README.mdx)
