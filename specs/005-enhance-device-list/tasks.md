# Task Checklist: Enhance Device List View

**Branch**: `005-enhance-device-list` | **Spec**: [specs/005-enhance-device-list/spec.md](spec.md)

## Checklist

- [ ] **1. Database & Schema Migration** <!-- id: 1 -->
  - [ ] 1.1. Create migration to add `ipv4_address`, `account_number`, and `remote_access_requested` to `devices` table. <!-- id: 1.1 -->
  - [ ] 1.2. Add indices for `ipv4_address`, `account_number`, and `approval_status`. <!-- id: 1.2 -->
  - [ ] 1.3. Update `Nixstasis.Devices.Device` schema with new fields and changeset validations. <!-- id: 1.3 -->
  - [ ] 1.4. Run migration and verify schema with a basic test. <!-- id: 1.4 -->

- [ ] **2. Device Context Logic** <!-- id: 2 -->
  - [ ] 2.1. Implement `Nixstasis.Devices.list_devices/1` with support for sorting (field, order) and filtering (status, search). <!-- id: 2.1 -->
  - [ ] 2.2. Implement `Nixstasis.Devices.approve_devices/1` and `Nixstasis.Devices.reject_devices/1` for bulk operations. <!-- id: 2.2 -->
  - [ ] 2.3. Implement `Nixstasis.Devices.set_remote_access/2` to toggle `remote_access_requested` flag. <!-- id: 2.3 -->
  - [ ] 2.4. Write unit tests for all new context functions (sorting, filtering, bulk actions). <!-- id: 2.4 -->
  - [ ] 2.5. Implement BDD-style context tests (Given/When/Then) for `approve_devices` and `reject_devices` workflows. <!-- id: 2.5 -->

- [ ] **3. LiveView List Implementation** <!-- id: 3 -->
  - [ ] 3.1. Create/Update `NixstasisWeb.DeviceLive.Index` to use `Phoenix.LiveView.stream` for the device table. <!-- id: 3.1 -->
  - [ ] 3.2. Implement sortable column headers (Device Name, Account #, Status). <!-- id: 3.2 -->
  - [ ] 3.3. Implement filter controls (Awaiting Approval, All) and search input. <!-- id: 3.3 -->
  - [ ] 3.4. Implement "Online/Offline" status indicator logic (> 5 mins = Offline). <!-- id: 3.4 -->
  - [ ] 3.5. Implement bulk selection UI and "Approve/Reject" action handlers. <!-- id: 3.5 -->
  - [ ] 3.6. Implement auto-dismissing toast logic (30s) for "Device Added" notifications. <!-- id: 3.6 -->

- [ ] **4. Device Detail Modal & Metrics** <!-- id: 4 -->
  - [ ] 4.1. Create `NixstasisWeb.DeviceLive.Show` component (or modal) triggered by row click. <!-- id: 4.1 -->
  - [ ] 4.2. Implement `mount/3` logic to set `remote_access_requested: true` and `terminate/2` (or close event) to set `false`. <!-- id: 4.2 -->
  - [ ] 4.3. Integrate ApexCharts (via JS Hook) for CPU, Memory, Disk Gauges in the modal. <!-- id: 4.3 -->
  - [ ] 4.4. Implement "PCP Data" tab fetching mock/real metric data and displaying historical line charts. <!-- id: 4.4 -->
  - [ ] 4.5. Add "Open Cockpit" button with dynamic URL generation (`https://{device_name}...`). <!-- id: 4.5 -->

- [ ] **5. Terminal & SSH Integration** <!-- id: 5 -->
  - [ ] 5.1. Implement `NixstasisWeb.TerminalChannel` to handle WebSocket <-> SSH communication. <!-- id: 5.1 -->
  - [ ] 5.2. Create `Nixstasis.Devices.SshClient` wrapper to manage Elixir `:ssh` connections via `frps`. <!-- id: 5.2 -->
  - [ ] 5.3. Add `assets/js/terminal.js` Hook to initialize `xterm.js` and connect to the Channel. <!-- id: 5.3 -->
  - [ ] 5.4. Integrate the Terminal component into the "Terminal" tab of the Detail Modal. <!-- id: 5.4 -->
  - [ ] 5.5. Implement BDD-style tests for `SshClient` connection states (mocking the underlying `:ssh` calls). <!-- id: 5.5 -->

- [ ] **6. Verification & Polish** <!-- id: 6 -->
  - [ ] 6.1. Write integration test for the full Device List flow (filter -> sort -> click). <!-- id: 6.1 -->
  - [ ] 6.2. Write integration test for Bulk Approval. <!-- id: 6.2 -->
  - [ ] 6.3. Verify UI responsiveness and DaisyUI styling compliance. <!-- id: 6.3 -->
  - [ ] 6.4. Manual verification of "Online/Offline" status and Toast behavior. <!-- id: 6.4 -->
