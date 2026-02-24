# Data Model: Devices Page and Device Modal Improvements

## Entity: DeviceListRow

Represents a single device row rendered in the Devices page list.

### Fields
- `device_id` (uuid/string): Stable device identifier used for row actions.
- `mac_address` (string): Primary row display field; rendered as clickable link.
- `product` (string | nil): Product association displayed in the Product column.
- `account_number` (string | nil): Account context used for filtering.
- `status` (enum): Current state shown in list (`pending`, `online`, `offline`, `approved`, `rejected` as supported by current domain model).
- `last_seen_at` (datetime | nil): Source for state freshness indicators.

### Validation Rules
- `mac_address` must be present and normalized for display and lookup.
- `status` must be one of allowed values.
- `product`/`account_number` may be null; null handling must be consistent in filter behavior.

## Entity: DeviceFilterState

Represents active table filters for the Devices page.

### Fields
- `product` (string | nil)
- `account_number` (string | nil)
- `status` (string | nil)
- `source` (enum: `click`, `manual`) indicates how filter was set (for telemetry/debugging only if needed)

### Relationships
- One `DeviceFilterState` applies to one Devices page session/view instance.

### Validation Rules
- At least one field must be non-null for active state.
- Each field maps to exact-match semantics by default.

### State Transitions
- `empty -> active`: first click on Product/Account Number/Status.
- `active -> active`: adding another column filter or replacing value in same column.
- `active -> partially_active`: removing one filter chip.
- `active|partially_active -> empty`: clear all action.

## Entity: DeviceModalSession

Represents active modal context for one selected device.

### Fields
- `selected_device_id` (uuid/string)
- `opened_from` (enum: `devices_list_mac_link`)
- `remote_access_requested` (boolean)
- `terminal_ready` (boolean)
- `pcp_data_ready` (boolean)

### Validation Rules
- `selected_device_id` required when modal is open.
- `remote_access_requested` set true on open and reset on close/failure cleanup per existing modal contract.

### State Transitions
- `closed -> opening`: MAC link clicked.
- `opening -> active`: modal data + remote access channels ready.
- `active -> degraded`: terminal or PCP stream interrupted; show retry guidance.
- `active|degraded -> closed`: user closes modal; cleanup triggers run.
