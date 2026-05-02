# Feature Specification: Enhance Device List View

**Feature Branch**: `005-enhance-device-list` **Created**: 2026-02-04 **Status**: Draft **Input**: User description: "Improve Devices view. When adding a device, the product say "manual-entry", but this view is meant to approve devices that are allowed to register themselves with the service. This value should be either empty or "pending...". The toast after adding a device should fade away automatically after about 30 seconds if the user does not dismiss it themselves. The table should be sortable and filterable. I should be able to see devices awaiting approval only and a way to bulk approve or reject them. The table should also show the IPv4 address as well as the account number, meaning the device table needs to store these two values in a column that is indexable. And instead of Last Seen, just an icon indicating online or offline, with offline being any device that has not polled the server in the last 5 minutes. Finally Clicking on a device needs to bring up a Modal with a detail overview. This overview should include Gauge style displays for CPU usage, memory usage and disk usage. The rest of the view should be a tabbed interface that allows the user to see Performance Co-Pilot (PCP) available data in an appropriate view, like a table, or chart, etc, etc. This will be accomplished triggering the device to start frpc. This will expose pcp's rest api's. Additionally, there should be a button to the right or the gauges that uses a airplane icon and say "Open Cockpit" which will open a new tab to the device's Cockpit instance using it's atom- prefix based DeviceName inserted into `https://{device_name}.device.<domain>`. In the tab interface there should include a tab that says "Terminal". This will start an in browser terminal emulator like xterm.js or something that uses it like ttyd. This will automatically start an ssh session to the device using the server and frps as the proxy. When the modal is closed, the "remote_access_requested" value should be set back to false so the client shutsdown frpc."

## Clarifications

### Session 2026-02-04
- Q: Do the IPv4 and Account Number fields already exist or need creation? → A: New fields & Migration - The fields do not exist; create a migration to add and index them.
- Q: How should table sorting and filtering be implemented? → A: LiveView Streams - Use Phoenix LiveView streams for efficient list management and real-time updates.
- Q: How should the PCP data be visualized in the Detail Modal? → A: Basic Time-Series Charts - Use line/area charts to show historical trends for key metrics (CPU/Mem/Disk/Net) instead of just tables.
- Q: How should the "In-browser Terminal" be implemented? → A: Phoenix Channels + SSH Client - Backend uses Elixir SSH client to connect (via frps) and streams to xterm.js via Channels.
- Q: Where should the new device logic reside in the codebase? → A: Dedicated Device Context - Create `Nixstasis.Devices` context for all device logic.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Device List Management and Visibility (Priority: P1)

The administrator needs a clear, sortable, and filterable view of all devices to efficiently manage the fleet. This includes seeing critical information like IPv4 addresses and account numbers at a glance, and understanding the device status instantly.

**Why this priority**: This is the core interface for the user. Without a usable list, management is impossible.

**Independent Test**: Can be tested by navigating to the device list, adding a device, and verifying the table structure, sorting, filtering, and status indicators without interacting with the detail modal.

**Acceptance Scenarios**:

1. **Given** a new device is added manually, **When** the confirmation toast appears, **Then** it should automatically disappear after 30 seconds if not dismissed.
2. **Given** a device is added or pending, **When** viewing the "Status" or "Type" column, **Then** it should display "pending..." or be empty instead of "manual-entry".
3. **Given** a list of devices, **When** the user clicks column headers, **Then** the list should sort by that column (e.g., Device Name, Account Number).
4. **Given** a large list of devices, **When** the user applies a filter, **Then** only matching devices should be shown.
5. **Given** a device that hasn't polled in 6 minutes, **When** viewing the list, **Then** the status icon should indicate "Offline".
6. **Given** a device that polled 1 minute ago, **When** viewing the list, **Then** the status icon should indicate "Online".

---

### User Story 2 - Bulk Approval Workflow (Priority: P1)

The administrator needs to efficiently approve or reject multiple devices that have self-registered and are awaiting authorization.

**Why this priority**: Managing device registration at scale requires bulk operations; doing this one-by-one is inefficient.

**Independent Test**: Can be tested by simulating multiple pending devices and performing bulk actions.

**Acceptance Scenarios**:

1. **Given** multiple devices in "awaiting approval" state, **When** the user filters for "awaiting approval", **Then** only those devices are shown.
2. **Given** multiple selected pending devices, **When** the user clicks "Approve", **Then** all selected devices are authorized.
3. **Given** multiple selected pending devices, **When** the user clicks "Reject", **Then** all selected devices are removed or marked as rejected.

---

### User Story 3 - Device Detail and Monitoring (Priority: P2)

The administrator needs to see detailed performance metrics and connect to the device for advanced troubleshooting.

**Why this priority**: Provides the necessary depth for investigating issues identified in the main list.

**Independent Test**: Can be tested by clicking a specific device and verifying the modal contents and triggering mechanisms.

**Acceptance Scenarios**:

1. **Given** the device list, **When** a user clicks on a device row, **Then** a detail Modal should open.
2. **Given** the detail modal is open, **When** it loads, **Then** `remote_access_requested` should be set to true for that device (triggering `frpc`).
3. **Given** the detail modal is open, **When** data is received, **Then** Gauges for CPU, Memory, and Disk usage should display current values.
4. **Given** the detail modal, **When** viewing the tabs, **Then** a "PCP Data" tab should be available showing metrics from the exposed API.
5. **Given** the detail modal is closed, **When** the action completes, **Then** `remote_access_requested` should be set to false.

---

### User Story 4 - Remote Access Tools (Priority: P3)

The administrator needs direct access to the device via Cockpit or Terminal for maintenance tasks.

**Why this priority**: Critical for deep-dive maintenance but relies on the monitoring connection being established (P2).

**Independent Test**: Can be tested by clicking the specific action buttons in the detail modal.

**Acceptance Scenarios**:

1. **Given** the detail modal is open, **When** the user clicks the "Open Cockpit" button (airplane icon), **Then** a new browser tab should open to `https://{atom-device-name}.<base-domain>`.
2. **Given** the detail modal is open, **When** the user selects the "Terminal" tab, **Then** an in-browser terminal (e.g., xterm.js) should initialize.
3. **Given** the terminal tab is active, **When** the user types, **Then** the input should be sent to the device via SSH over the `frps` proxy.

---

### Edge Cases

- **frpc Start Failure**: If the device fails to start the proxy, the Modal should display a timeout error toast ("Unable to establish connection") after 15 seconds.
- **Missing Data**: Devices with missing `ipv4_address` or `account_number` must display "N/A" in the table cells; sorting should place these at the end.
- **Cockpit Popup Blocked**: The "Open Cockpit" button should trigger a standard window open event; if blocked, the browser's native UI will handle the notification.
- **SSH Connection Drop**: If the SSH socket disconnects, the terminal view should freeze and display a "Connection Lost - Refresh to retry" overlay.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a sortable and filterable table of devices using **Phoenix LiveView Streams** for performance.
- **FR-002**: Device table MUST include columns for IPv4 Address and Account Number (stored as indexable fields).
- **FR-003**: System MUST display an Online/Offline status icon based on polling activity (Offline = > 5 minutes since last poll).
- **FR-004**: System MUST allow filtering for devices "awaiting approval" and support bulk Approve/Reject actions.
- **FR-005**: When adding a manual device, the status text MUST be empty or "pending..." (replacing "manual-entry").
- **FR-006**: Success toasts for device addition MUST auto-dismiss after 30 seconds.
- **FR-007**: Clicking a device MUST open a detail Modal.
- **FR-008**: Opening the detail Modal MUST set the device's `remote_access_requested` flag to `true`.
- **FR-009**: Closing the detail Modal MUST set the device's `remote_access_requested` flag to `false`.
- **FR-010**: Detail Modal MUST display Gauge visualizations for CPU, Memory, and Disk usage.
- **FR-011**: Detail Modal MUST provide a tabbed interface including a view for Performance Co-Pilot (PCP) data, visualized using **Time-Series Charts** (e.g., Line/Area) for historical trends.
- **FR-012**: Detail Modal MUST include an "Open Cockpit" button that opens `https://{device_name}.<base-domain>` in a new tab.
- **FR-013**: Detail Modal MUST include a "Terminal" tab that establishes an SSH session via `frps` proxy using a web-based terminal emulator (**xterm.js**) powered by **Phoenix Channels** and a backend Elixir SSH client.

### Assumptions

- Devices have the necessary agents installed (frpc, PCP, Cockpit) to support the requested features.
- The server infrastructure allows the necessary proxy connections (frps).
- Users accessing these features have appropriate permissions.

### Key Entities *(include if feature involves data)*

- **Device**: Represents a managed unit.
    - **Context**: `Nixstasis.Devices`
    - **Attributes**: DeviceName, IPv4Address, AccountNumber, LastPolledTime, RemoteAccessRequested (boolean), ApprovalStatus.
    - **Schema Updates**: Add `ipv4_address` (string/inet) and `account_number` (string) columns. Both must be indexed for performant filtering/sorting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Admin can filter the device list to show only "Offline" devices in under 5 seconds.
- **SC-002**: Admin can approve 50+ pending devices in a single bulk action.
- **SC-003**: Opening a device detail modal establishes a visible metric stream (CPU/Mem) within reasonable network latency (e.g., < 10s).
- **SC-004**: SSH terminal session connects and accepts input.
