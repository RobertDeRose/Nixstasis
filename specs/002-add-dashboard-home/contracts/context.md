# Context Interface: Nixstasis.Dashboard

**Feature**: `002-add-dashboard-home`

This document defines the internal API (Context functions) used by the Dashboard LiveView.

## Functions

### `get_vital_stats/0`

Retrieves the current aggregated statistics for the dashboard.

- **Signature**: `get_vital_stats() :: %DashboardStats{}`
- **Returns**:
  ```elixir
  %{
    total_devices: 150,
    online_devices: 145,
    offline_devices: 5,
    pending_approvals: 2,
    active_alerts: 1
  }
  ```

## PubSub Events

The Dashboard subscribes to the following topics to trigger updates.

### Topic: `devices`

- **Message**: `{:device_registered, device}`
  - **Action**: Increment `total_devices`, potentially `pending_approvals` (if default is pending).
  - **Refetch**: `total_devices`, `pending_approvals`.

- **Message**: `{:device_status_changed, device_id, new_status}`
  - **Action**: Update `online_devices` / `offline_devices`.
  - **Refetch**: `online_devices`, `offline_devices`.

### Topic: `alerts`

- **Message**: `{:alert_created, alert}`
  - **Action**: Increment `active_alerts`.
  - **Refetch**: `active_alerts`.

- **Message**: `{:alert_resolved, alert}`
  - **Action**: Decrement `active_alerts`.
  - **Refetch**: `active_alerts`.
