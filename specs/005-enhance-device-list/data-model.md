# Data Model: Enhance Device List View

**Branch**: `005-enhance-device-list` | **Date**: 2026-02-04

## Entity: Device

**Context**: `Nixstasis.Devices`
**Table**: `devices` (assumed existing, or creating new if migrating logic)

### Attributes

| Field | Type | Constraint | Description |
|-------|------|------------|-------------|
| `id` | `binary_id` | PK | Standard UUID primary key. |
| `name` | `string` | Unique, Not Null | The device identifier (e.g., `atom-xyz`). |
| `ipv4_address` | `inet` | Nullable, Indexed | **[NEW]** The LAN/WAN IP of the device. |
| `account_number` | `string` | Nullable, Indexed | **[NEW]** Customer account identifier. |
| `last_polled_at` | `utc_datetime` | Nullable | Timestamp of last heartbeat. Used to compute Online/Offline. |
| `approval_status` | `string` | Default: "pending" | Enum: `pending`, `approved`, `rejected`. |
| `remote_access_requested` | `boolean` | Default: `false` | **[NEW]** Flag to trigger `frpc` start on the device. |

### Validations

- `ipv4_address`: Must be a valid IPv4 address format if present.
- `account_number`: Format validation (if applicable to business rules).
- `approval_status`: Must be one of `[:pending, :approved, :rejected]`.

### State Transitions

1.  **Registration**:
    - New device polls -> Created with `approval_status: :pending`.
2.  **Approval**:
    - Admin clicks "Approve" -> `approval_status` becomes `:approved`.
3.  **Rejection**:
    - Admin clicks "Reject" -> `approval_status` becomes `:rejected` (or record deleted).
4.  **Monitoring**:
    - Admin opens Modal -> `remote_access_requested` -> `true`.
    - Admin closes Modal -> `remote_access_requested` -> `false`.

### Indices

- `index_devices_on_ipv4_address`
- `index_devices_on_account_number`
- `index_devices_on_approval_status`
