# Device Groups

Device groups provide manual fleet organization in the **Devices** view. A device can belong to multiple groups, and group membership does not change registration, approval, heartbeat, command, remote-access, or API-token behavior.

No public API or client command manages groups. Group metadata and memberships are server-owned operator data managed through the Phoenix LiveView UI.

## Permissions and visibility

Group access follows the trusted device permissions established for the browser session:

- An unscoped device manager can create, edit, archive, restore, and permanently delete group metadata. This manager can also change memberships for any device.
- A scoped device manager can see only groups containing at least one accessible device. Counts include accessible devices only. The manager can add or remove selected accessible devices only in those visible groups.
- A view-only operator can see groups and counts only where the operator can see a member device. Metadata and membership controls are unavailable.
- A group with no accessible members is not disclosed to a scoped operator.

The server checks permissions again for every metadata or membership action. If device access changes after selection, the complete operation fails without a partial membership update.

## Create and maintain groups

Open **Devices → Groups**. Unscoped device managers can:

1. Select **New group** and enter a name and optional description.
2. Use **Edit** to change active group metadata.
3. Use **Archive** to remove a group from normal lists, membership targets, and route filters.
4. Select **Show archived**, then **Restore** to return a group to active use.
5. Select **Delete permanently** and confirm to remove an archived group that has no memberships.

Archiving is the normal removal action. It preserves the group identity and every membership, so restoring the group restores the same organization. Permanent deletion is intentionally restricted to archived, empty groups.

Group names are unique without regard to letter case across active and archived groups. Archiving a group does not make its name available for reuse.

## Change memberships

To add or remove devices:

1. Select one or more devices in the existing Devices table.
2. Choose an active, visible group in the bulk action bar.
3. Select **Add to group** or **Remove from group**.

Adding an existing membership or removing a missing membership succeeds without making another change. Every multi-device action is atomic: an archived or missing group, a missing device, or changed authorization prevents all requested changes.

If a scoped removal eliminates the final accessible membership in a group, that group and its membership target disappear from the scoped view.

## Filter and review membership

On desktop layouts, the **Groups** column shows up to two active memberships for each device and a count for additional groups. Select a group badge to filter the device list.

The route stores the stable group UUID in the `group_id` query parameter. The filter composes with search, sort, product, account number, IPv4 address, approval status, and connectivity status. The active-filter chip displays the current group name rather than its UUID.

Small screens omit the dense membership-summary column; open **Groups** to review visible groups and scoped membership counts without widening the primary table.

Invalid, archived, deleted, or unauthorized group IDs all produce the same unavailable state and disclose no group metadata or devices. Select **Continue without group filter** to remove the unavailable route state.

## Audit and retention

Successful group creation, update, archive, restore, permanent deletion, membership addition, and membership removal emit a structured `device group audit` log event after the database transaction commits. Each event contains:

- action;
- trusted actor ID;
- UTC timestamp;
- group ID; and
- affected device IDs.

Audit events are not stored in a separate Nixstasis database table. Retention, export, and access control therefore follow the deployment's structured-log collection policy. The in-process audit PubSub topic is for subscribers and is not a durable retention mechanism. UI refreshes use a separate payload-free notification and do not carry actor or device details.

## Resolve conflicts and stale state

- **A group with that name already exists:** choose another name. The conflict can come from an active or archived group.
- **Remove every device before permanently deleting this group:** restore the group if needed, remove all memberships, archive it again, and repeat permanent deletion.
- **That group is archived or no longer available:** refresh the Devices view or restore the group before retrying.
- **Your device access changed:** refresh the page. Ask an administrator to restore access if the devices should remain in scope.
- **Operator identity is unavailable:** sign in again. Production mutations fail closed without a trusted actor identity.
- **Requested group is unavailable:** use **Continue without group filter**. The UI intentionally does not reveal whether the ID is invalid, archived, deleted, or outside the operator's scope.

A failed bulk membership action does not require data repair because the transaction rolls back every requested change.

## Related architecture

- [Architecture Overview](../architecture.md)
- [Server Devices](../modules/server-devices.md)
- [Device Detail Page](../features/device-detail-page/index.md)
