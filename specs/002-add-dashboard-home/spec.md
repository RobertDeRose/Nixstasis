# Feature Specification: IoT Dashboard Homepage

**Feature Branch**: `002-add-dashboard-home`
**Created**: 2026-02-01
**Status**: Draft
**Input**: User description: "Building off what was accomplished in `specs/001-iot-device-monitoring/` add a homepage that shows vital stats and navigation for the implemented routes"

## Clarifications

### Session 2026-02-01

- Q: How should the dashboard data be refreshed? → A: Real-time: Use LiveView for instant updates.
- Q: What historical context should be shown for the vital stats? → A: Snapshot Only: Show current counts without historical trends, updating in real-time.
- Q: How should user permissions affect dashboard visibility? → A: Single Role: All users have full visibility; no RBAC enforcement in this iteration.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Vital Statistics (Priority: P1)

As an IoT Operator, I want to see a high-level overview of my device fleet's health immediately upon login, so that I can quickly identify if there are critical issues like offline devices or pending approvals requiring attention.

**Why this priority**: Provides immediate situational awareness and directs the user's attention to problem areas.

**Independent Test**: Seed the database with known quantities of devices (online, offline, pending) and alerts. Load the homepage and verify the displayed numbers match the seeded data.

**Acceptance Scenarios**:

1. **Given** a system with registered devices, **When** the operator loads the homepage, **Then** they see the total count of devices.
2. **Given** some devices are reporting heartbeats and others are not, **When** the operator views the homepage, **Then** they see a breakdown of Online vs. Offline devices.
3. **Given** devices waiting in the "Pending Approval" list, **When** the operator views the homepage, **Then** they see the count of pending approvals.
4. **Given** active alerts in the system, **When** the operator views the homepage, **Then** they see the count of active alerts.
5. **Given** the dashboard is open, **When** a new device registers or goes offline, **Then** the relevant counter updates automatically without a page reload.

---

### User Story 2 - Navigation to Core Features (Priority: P1)

As an IoT Operator, I want clear navigation links to the specific management sections (Devices, Approvals, Alerts, Reports) directly from the homepage, so that I can efficiently perform tasks based on the overview stats.

**Why this priority**: Essential for usability; the homepage serves as the central hub for the application.

**Independent Test**: Click each navigation link on the homepage and verify it redirects to the correct route/page.

**Acceptance Scenarios**:

1. **Given** the homepage is loaded, **When** the user clicks "Manage Devices", **Then** they are taken to the Device List view.
2. **Given** the homepage is loaded, **When** the user clicks "Pending Approvals", **Then** they are taken to the Approval Workflow view.
3. **Given** the homepage is loaded, **When** the user clicks "View Alerts", **Then** they are taken to the Alerts view.
4. **Given** the homepage is loaded, **When** the user clicks "Reports", **Then** they are taken to the Custom Report Builder.

---

### Edge Cases

- What happens if there are zero devices in the system? (Should show zeros, not errors)
- What happens if the stats calculation service is down or slow? (Should handle gracefully, maybe show loading state or cached data)
- What happens if a user doesn't have permission to view certain stats (e.g., read-only user vs admin)? (Handled by Single Role assumption: all users see all stats)

## Assumptions & Dependencies

- **Assumption**: The "implemented routes" refer to the features defined in `specs/001-iot-device-monitoring/` (Device List, Pending List, Alerts, Report Builder).
- **Assumption**: "Online" status is determined by the same logic as the "Offline Device Alerts" (heartbeat within window).
- **Assumption**: The homepage is the default landing page for the application.
- **Assumption**: The implementation will utilize LiveView for real-time capabilities.
- **Dependency**: The backend API provides endpoints to fetch these aggregated statistics efficiently.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display the **Total Device Count** (sum of all registered devices).
- **FR-002**: System MUST display the **Device Connectivity Status** (count of Online vs. Offline devices).
- **FR-003**: System MUST display the **Pending Approval Count** (number of devices in the pending list).
- **FR-004**: System MUST display the **Active Alert Count** (number of currently unresolved alerts).
- **FR-005**: System MUST provide a prominent navigation element (link/button) to the **Device Management** section.
- **FR-006**: System MUST provide a prominent navigation element to the **Device Approvals** section.
- **FR-007**: System MUST provide a prominent navigation element to the **Alerts** section.
- **FR-008**: System MUST provide a prominent navigation element to the **Reports** section.
- **FR-009**: The Vital Stats cards/sections MUST be clickable, linking to the relevant detailed view (e.g., clicking "5 Offline Devices" goes to Device List filtered by "Offline").
- **FR-010**: The dashboard statistics MUST update in real-time as the underlying data changes.

### Key Entities

- **Dashboard Summary**: An aggregation object containing counts for Devices (Total, Online, Offline), Pending Approvals, and Alerts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The homepage loads and displays all vital stats within 2 seconds of request under normal load.
- **SC-002**: 100% of navigation links on the homepage successfully direct the user to the correct target page.
- **SC-003**: The displayed statistics exactly match the actual database counts at the time of page load (data integrity).
- **SC-004**: Users can identify the number of offline devices within 5 seconds of logging in.
- **SC-005**: Dashboard data updates in real-time (sub-second) when underlying state changes without page reload.
