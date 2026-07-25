<!-- workflow-migration:legacy-markdown-to-beads -->

# Device Detail Page

## Feature Name

`device-detail-page`

## Goal

Expose device details from the Devices page workflow without the obsolete modal
REST endpoints, preserving list context while operators inspect individual
devices.

## Users

- Operations users browsing the device fleet.
- Administrators inspecting individual device status and ownership details.

## Requirements

- Present the Devices page with key attributes needed for monitoring and selection.
- Apply additive AND filtering across Product, Account Number, and Status values.
- Support individual filter-chip removal and clear-all behavior.
- Provide an explicit MAC Address entrypoint for each device row to open details.
- Open device details through the route-backed `/devices/:id` LiveView flow while
  preserving active filters and return context.
- Do not restore the obsolete modal open/close REST endpoints.
- Display meaningful empty, loading, and error states.
- Prevent unauthorized users from seeing restricted device details.
- Keep detail content current at open/refresh time.
- Keep behavior consistent across desktop and mobile.

## Proposed Design

Device detail is owned by the existing Devices LiveView flow and browser route,
not the obsolete `/api/v1/devices/:device_id/modal` API surface. The list page
stays optimized for finding devices, while the route-backed detail view may be
rendered as a modal overlay so deeper inspection and action context do not lose
the user's filter state.

Remote-access detail behavior is shared with the older device-list management
backlog: detail views can expose PCP metrics, terminal access, and Cockpit links,
but those tabs must show degraded/retry states when the device or tunnel is not
available.

## Edge Cases

- Empty device list.
- Device deleted before or during detail navigation.
- Large device lists requiring efficient rendering.
- Network loss during detail load.
- User loses access to sensitive device details.

## Validation

- Users can find a target device from the list quickly.
- Opening `/devices/:id` shows the correct device and supports return navigation
  or modal close back to the filtered list.
- Missing/deleted/unauthorized devices show clear recovery states.
