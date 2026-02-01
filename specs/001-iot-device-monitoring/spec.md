# Feature Specification: IoT Device Monitoring

**Feature Branch**: `001-iot-device-monitoring`
**Created**: 2026-01-31
**Status**: Draft
**Input**: User description:
            "Build an application that provides an API for IoT devices to self register with the server..."

## Clarifications

### Session 2026-02-01

- Q: How does the system handle conflicting schemas for the same device ID (re-registration)? → A: Upsert: Update the existing device's schema definition with the new one (potentially merging fields).
- Q: How are heartbeats authenticated to prevent spoofing? → A: Token-based: Registration returns a persistent API token sent with heartbeats.
- Q: How should the report builder handle field type conflicts (e.g., string vs number)? → A: Allow the user to handle.
- Q: How does the system handle a massive surge in heartbeats (DoS protection)? → A: Rate Limit (Tunable): Return 429 status code if frequency exceeds a configurable threshold.
- Q: What are the notification channels for offline alerts? → A: Dashboard, Email, and Webhook support.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Device Self-Registration & Grouping (Priority: P1)

As a device integrator, I want my IoT devices to self-register with a schema that includes a "product" key, so that
devices are automatically grouped by product type and the server knows how to interpret their data.

**Why this priority**: Foundation for device management and data organization.

**Independent Test**: Send registration requests with and without the "product" key. Verify successful registration puts
devices in the correct product group. Verify requests missing the "product" key are rejected.

**Acceptance Scenarios**:

1. **Given** a new IoT device with a valid schema including the mandatory `product` key, **When** it sends a
   registration request, **Then** the server processes the registration request.
2. **Given** a registration request missing the `product` key in the schema, **When** it is sent, **Then** the server
   rejects the registration with a schema validation error.
3. **Given** registered devices with the same `product` key, **When** an operator views the device list, **Then** these
   devices are grouped together.

---

### User Story 2 - Device Approval Workflow (Priority: P1)

As a security administrator, I want to explicitly approve devices by their MAC address before they can fully register,
and view pending attempts, so that I maintain control over which hardware accesses the network.

**Why this priority**: Security requirement to prevent unauthorized devices from registering.

**Independent Test**: Attempt registration with an unapproved MAC. Verify it fails but appears in "Pending Approval".
Approve it via Dashboard. Retry registration and verify success.

**Acceptance Scenarios**:

1. **Given** a device with a MAC address NOT in the approved list, **When** it attempts to register, **Then** the
   registration is denied, and the MAC address is added to the "Pending Approval" list.
2. **Given** a device in the "Pending Approval" list, **When** an admin approves it via the Dashboard, **Then** its MAC
   address is moved to the approved list.
3. **Given** a device with an approved MAC address, **When** it attempts to register, **Then** the registration
   succeeds.
4. **Given** an admin wants to pre-approve devices, **When** they add MAC addresses to the approved list manually,
   **Then** those devices can register immediately upon connection.

---

### User Story 3 - Heartbeat & Command Delivery (Priority: P1)

As a device operator, I want devices to report their presence and receive pending commands during check-ins so that I
can maintain communication and control over the fleet.

**Why this priority**: Critical for monitoring device health and enabling bidirectional communication.

**Independent Test**: Simulate a device sending a heartbeat. Verify it receives a success response. Queue a command for
the device, send another heartbeat, and verify the command is returned in the response.

**Acceptance Scenarios**:

1. **Given** a registered device, **When** it sends a heartbeat message, **Then** the server acknowledges the heartbeat
   to confirm connectivity.
2. **Given** a device with pending commands queued on the server, **When** it sends a heartbeat, **Then** the server
   responds with the list of pending commands.
3. **Given** a device with no pending commands, **When** it sends a heartbeat, **Then** the server responds with a
   simple acknowledgement (no commands).

---

### User Story 4 - Offline Device Alerts (Priority: P2)

As a system administrator, I want to view alerts for devices that have stopped reporting so that I can identify and
troubleshoot disconnected units.

**Why this priority**: Essential for operational reliability and minimizing downtime.

**Independent Test**: Configure a "lost contact" threshold. Stop sending heartbeats from a test device. Verify an alert
appears on the dashboard after the time window expires.

**Acceptance Scenarios**:

1. **Given** a configurable timeout window (e.g., 5 minutes), **When** a device fails to send a heartbeat within that
   duration, **Then** the system generates an alert.
2. **Given** the dashboard alerts view, **When** an offline alert is generated, **Then** the device is listed as
   "Offline" or "Missing".
3. **Given** a device that was offline, **When** it resumes sending heartbeats, **Then** the alert is resolved or
   updated to show the device is back online.

---

### User Story 5 - Data-Driven Alerts (Priority: P3)

As a data analyst, I want to configure alerts based on specific values reported by devices so that I am notified of
critical conditions (e.g., high temperature, low battery).

**Why this priority**: Adds value by automating monitoring of device telemetry.

**Independent Test**: Define a rule (e.g., "temp > 100"). Simulate a device reporting data violating this rule. Verify
an alert is triggered.

**Acceptance Scenarios**:

1. **Given** a specific data field defined in a device's schema, **When** a user creates an alert rule for that field
   (e.g., value threshold), **Then** the system monitors incoming data for that condition.
2. **Given** an active alert rule, **When** a device reports data satisfying the condition, **Then** an alert is
   displayed on the dashboard.

---

### User Story 6 - Custom Reports & Overviews (Priority: P3)

As a user, I want to build custom dashboard pages using any data from device schemas and combine different device types,
so that I can visualize cross-product metrics relevant to my specific operations.

**Why this priority**: Provides high-level visibility and flexibility for diverse fleet management.

**Independent Test**: Create a new report view. Select data fields from two different product schemas. Save the view.
Verify the dashboard displays the aggregated data correctly.

**Acceptance Scenarios**:

1. **Given** the custom report builder, **When** a user selects data fields from the schemas of different device types
   (products), **Then** the system generates a unified view/report containing that data.
2. **Given** a custom report, **When** new data arrives from devices, **Then** the report updates to reflect the latest
   values (or on refresh).
3. **Given** a saved report configuration, **When** a user accesses the "Overviews" section, **Then** they can load and
   view the custom report.

### Edge Cases

- What happens when a device registers with a schema that has duplicate keys?
- How does the system handle conflicting schemas for the same device ID?
- What happens if a heartbeat is received for an unregistered device?
- How does the system handle a massive surge in heartbeats (DoS protection)?
- What happens if a user tries to create a report with incompatible data types from different schemas?

## Assumptions & Dependencies

- **Assumption**: The registration process (US1) establishes the necessary security context (tokens/keys) for subsequent
  heartbeats (US2).
- **Assumption**: The "offline" timeout window (US3) is initially a global setting applied to all devices, though the
  architecture should support per-device overrides in the future.
- **Assumption**: "Simple reply" to a heartbeat implies a lightweight acknowledgment payload to minimize bandwidth.
- **Assumption**: There is an existing mechanism or a new requirement (FR-007) to input/queue commands for devices; this
  spec focuses on *delivering* them via heartbeat, not the UI to create them (unless implied by "requests it has for the
  client").
- **Assumption**: MAC Address is used as the unique identifier for device approval.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow devices to register themselves by providing a unique identifier (MAC Address) and a data
  schema.
- **FR-001a**: If a device registers with a schema that differs from its stored record, the system MUST update (upsert) the existing schema definition.
- **FR-001b**: Upon successful registration, the system MUST return a persistent API token to the device.
- **FR-002**: System MUST parse the provided schema to identify searchable fields. The schema definition MUST include
  an `indexed_fields` array listing keys that require optimization for reports.
- **FR-003**: System MUST require a top-level `product` key in every device schema and reject registration if missing.
- **FR-004**: System MUST store device reported data in a format that supports dynamic fields (different devices having
  different data).
- **FR-005**: System MUST allow devices to send periodic heartbeat messages.
- **FR-005a**: Devices MUST include their API token in the heartbeat request header for authentication.
- **FR-005b**: System MUST enforce a configurable rate limit on heartbeats per device and return HTTP 429 if exceeded.
- **FR-006**: System MUST respond to heartbeats with a standard acknowledgement if no actions are required.
- **FR-007**: System MUST respond to heartbeats with pending commands/requests if any exist for that specific device.
- **FR-008**: System MUST provide a mechanism to queue commands/requests for a specific device.
- **FR-009**: System MUST provide a Dashboard with an "Alerts" view.
- **FR-010**: System MUST generate an alert when a device has not sent a heartbeat within a configurable time window.
- **FR-010a**: Alerts MUST be displayed on the Dashboard and dispatched via Email and Webhook (if configured).
- **FR-011**: Users MUST be able to configure the duration of the "offline" time window.
- **FR-012**: Users MUST be able to define custom alert rules based on values of the dynamic data fields reported by
  devices.
- **FR-013**: System MUST deny registration for any device whose MAC Address is not in the "Approved List".
- **FR-014**: System MUST log denied registration attempts (MAC Addresses) to a "Pending Approval" list.
- **FR-015**: System MUST provide a Dashboard view to manage device approvals (view Pending, Approve, Add new MACs).
- **FR-016**: System MUST provide a custom report builder in the Dashboard that allows users to select any schema fields
  from any combination of client types/products.
- **FR-016a**: If selected fields have conflicting data types across schemas, the system MUST prompt the user to resolve the conflict (e.g., choose casting or exclusion).

### Key Entities

- **Device**: Represents a physical unit, identified by a MAC Address/Unique ID, associated with a specific Schema and
  Product.
- **Schema**: Defines the structure of data a device reports, including mandatory `product` key and indexable fields.
- **Approved List**: A registry of MAC addresses allowed to register.
- **Pending List**: A registry of MAC addresses that attempted registration but were denied.
- **Heartbeat**: A periodic signal from the device indicating it is online.
- **Command**: An instruction queued by the server to be delivered to the device during the next heartbeat.
- **Alert Rule**: A condition defined by a user (time-based or data-value-based) that triggers an Alert.
- **Custom Report**: A user-defined configuration for visualizing aggregated data from multiple device schemas.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of registered devices with valid schemas can have their "searchable" fields queried via the system.
- **SC-002**: Device heartbeats are acknowledged or responded to (with commands) in real-time (user-perceived check-in).
- **SC-003**: Offline alerts are generated within 60 seconds of the configurable threshold being crossed.
- **SC-004**: Operators can visually identify all currently offline devices in the Dashboard within 1 click.
- **SC-005**: Users can define alert rules on any field present in a registered device's schema.
- **SC-006**: Unapproved devices appear in the "Pending Approval" list within 30 seconds of a failed registration
  attempt.
- **SC-007**: Users can generate a multi-product overview report using the custom builder without engineering support.
