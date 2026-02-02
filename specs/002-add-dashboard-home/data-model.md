# Data Model: IoT Dashboard Homepage

**Feature**: `002-add-dashboard-home`

## New Logical Entities

*Note: No new database tables are introduced in this feature. These are in-memory structures used for the dashboard.*

### DashboardStats

A summary struct used to render the homepage view.

- **Structure**: Map / Elixir Struct
- **Fields**:
  - `total_devices` (Integer) - Count of all devices.
  - `online_devices` (Integer) - Count of devices with recent heartbeat.
  - `offline_devices` (Integer) - Count of devices missing heartbeat.
  - `pending_approvals` (Integer) - Count of devices in `pending` approval status.
  - `active_alerts` (Integer) - Count of `active` alerts.

## Existing Entity Usage

### Device
- **Source**: `devices` table.
- **Usage**:
  - Count all rows -> `total_devices`
  - Count where `approval_status = 'pending'` -> `pending_approvals`
  - Count where `last_seen_at > (now - window)` -> `online_devices`

### Alert
- **Source**: `alerts` table.
- **Usage**:
  - Count where `status = 'active'` -> `active_alerts`
