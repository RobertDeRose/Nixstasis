<!-- workflow-migration:legacy-markdown-to-beads -->

# Dashboard Home

## Feature Name

`dashboard-home`

## Goal

Provide a LiveView homepage that gives operators immediate situational awareness
for the device fleet and direct navigation into core workflows.

## Users

- IoT operators monitoring fleet health.
- Administrators reviewing pending approvals and active alerts.

## Requirements

- Show total device count.
- Show online and offline device counts using the same heartbeat-window logic as offline alerts.
- Show pending approval count.
- Show active alert count.
- Provide prominent navigation to Devices, Approvals, Alerts, and Reports.
- Make relevant stat cards clickable and route to the corresponding filtered/detail view where supported.
- Update stats in real time without requiring a page reload.
- Render sensible zero-data, loading, and degraded-data states.

## Proposed Design

The dashboard home is the default landing page. It reads aggregated summary data
from the dashboard/server contexts and renders compact statistic cards plus
workflow navigation. LiveView updates keep the snapshot fresh as devices register,
heartbeats arrive, approvals change, and alerts resolve.

Dashboard aggregates follow the same device-data authorization scope as device-backed
views. Unscoped authorized operators see the full fleet summary; device-scoped
operators see counts only for their allowed device IDs. Missing or malformed device
scope fails closed to zero-valued device-backed statistics.

## Validation

- Seed devices, approvals, and alerts; verify displayed counts match the authorized device scope.
- Verify malformed or missing device-data authorization cannot expose fleet-wide aggregate counts.
- Verify navigation links reach the expected routes.
- Verify empty-state counts display as zero rather than errors.
- Verify updates arrive without manual page reload.
