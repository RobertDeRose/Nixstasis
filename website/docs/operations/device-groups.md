# Device Groups

Groups let you organize the fleet your own way in the **Devices** view, by site, customer, hardware batch, or anything
else. A device can be in any number of groups. Groups are purely for organizing and filtering: being in a group never
changes how a device registers, gets approved, sends heartbeats, runs commands, or is reached remotely.

Groups are managed only in the web UI. There is no API or client command for them.

## Who can do what

What you can see and change depends on your device permissions:

- **Device managers with access to every device** can create, edit, archive, restore, and permanently delete groups,
  and change membership for any device.
- **Device managers limited to some devices** see only groups that contain at least one of their devices, and the
  counts include only those devices. They can add or remove their own devices, but only in groups they can see.
- **View-only operators** see a group, and its count, only if they can see at least one device in it. They cannot
  change anything.

A group with none of your devices in it is hidden from you entirely.

The server checks permissions again on every change. If your access changes after you select some devices, the whole
action fails; nothing is half-applied.

## Create and maintain groups

Open **Devices → Groups**. If you can manage every device, you can:

1. Select **New group** and enter a name and, optionally, a description.
2. Use **Edit** to change an active group's name or description.
3. Use **Archive** to take a group out of lists, membership choices, and filters.
4. Select **Show archived**, then **Restore**, to bring an archived group back.
5. Select **Delete permanently**, and confirm, to remove an archived group that has no members.

Archive is the normal way to retire a group. It keeps the group and all its memberships, so restoring it puts
everything back exactly as it was. Permanent deletion is only allowed for archived, empty groups, so you cannot wipe
out a group's memberships by accident.

Names are unique, ignoring case, across active and archived groups, so archiving a group does not free its name. Names
can be up to 120 characters and descriptions up to 500.

## Add and remove devices

1. Select one or more devices in the Devices table.
2. Choose an active group in the bulk action bar.
3. Select **Add to group** or **Remove from group**.

Adding a device that is already in the group, or removing one that is not, simply does nothing. A multi-device action
either succeeds completely or changes nothing: if the group is archived or missing, a device is missing, or your
access changed, none of the changes are made.

If you can only see some devices and you remove the last of yours from a group, that group disappears from your view.

## Filter by group

On wide screens, the **Groups** column shows up to two of each device's active groups, plus a count of any others.
Select a group badge to filter the list to that group.

The filter is saved in the URL as `group_id`, using the group's UUID, so you can bookmark or share it. It works
together with search, sorting, and the product, account number, IPv4 address, approval, and connectivity filters. The
filter chip shows the group's name, not its UUID.

On small screens the Groups column is hidden to save space; open **Groups** to see the groups and counts available to
you.

If the URL names a group that does not exist, is archived or deleted, or that you cannot see, you get the same
"unavailable" message in every case, so nothing is revealed about groups outside your access. Select **Continue without
group filter** to clear it.

## Audit trail

Every successful change to a group or its members writes a structured `device group audit` log event once the change
is saved. Each event records:

- the action;
- who did it;
- when, in UTC;
- the group ID;
- the device IDs affected.

These events go to your logs, not to a Nixstasis table, so how long they are kept, how they are exported, and who can
read them is up to your log collection. The audit PubSub topic inside the server is for live subscribers only and keeps
nothing. The separate notification that refreshes the UI carries no details about who changed what.

## Fix common problems

- **A group with that name already exists:** pick another name. The existing group might be archived.
- **Remove every device before permanently deleting this group:** restore the group, remove its members, archive it
  again, and then delete it.
- **That group is archived or no longer available:** refresh the Devices view, or restore the group, then try again.
- **Your device access changed:** refresh the page. If the devices should still be yours, ask an administrator to
  restore your access.
- **Operator identity is unavailable:** sign in again. In production, changes are refused unless the server knows who
  you are.
- **Requested group is unavailable:** select **Continue without group filter**. The message deliberately does not say
  whether the group is invalid, archived, deleted, or just not visible to you.

If a bulk action fails, there is nothing to clean up: the whole change is rolled back.

## Related pages

- [Architecture Overview](../architecture.md)
- [Server Devices](../modules/server-devices.md)
- [Device Detail Page](../features/device-detail-page/index.md)
