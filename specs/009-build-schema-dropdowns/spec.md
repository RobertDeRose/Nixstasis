# Feature Specification: Schema-Driven Builder Dropdowns

**Feature Branch**: `009-build-schema-dropdowns` **Created**: 2026-02-14 **Status**: Draft **Input**: User description: "Use stary script schemas to build dropdown menu for alert and report builder"

## Clarifications

### Session 2026-02-14

- Q: How should schema version selection behave between alert and report builders? → A: Each builder uses its own explicitly selected schema version (independent per alert/report builder).
- Q: What should happen to selections invalidated by schema changes? → A: Automatically clear invalid selections and show inline "reselect required" feedback.
- Q: What is the maximum acceptable dropdown option load time after schema selection? → A: <=2 seconds.
- Q: What should happen if a user loses schema access while editing? → A: Clear options, block save, and show an authorization message until access is restored.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Select Valid Fields from Schema (Priority: P1)

As a builder user creating an alert or report, I can pick fields from dropdown menus that are generated from the schema so I do not need to type field names manually.

**Why this priority**: This is the core value of the feature and prevents invalid manual entry in the most common workflow.

**Independent Test**: Can be fully tested by opening either builder, choosing a schema, and confirming dropdown options are populated from that schema and can be selected.

**Acceptance Scenarios**:

1. **Given** a user is on the alert builder with a selected schema, **When** they open a field dropdown, **Then** they see only selectable fields defined by that schema.
2. **Given** a user is on the report builder with a selected schema, **When** they open a field dropdown, **Then** they see only selectable fields defined by that schema.
3. **Given** dropdown options are shown, **When** the user selects one option, **Then** the selected value is applied to the current builder form.

---

### User Story 2 - Keep Dropdowns in Sync with Schema Changes (Priority: P2)

As a builder user, when I switch to a different schema I want the dropdown menus to refresh so I only see options relevant to my current schema context.

**Why this priority**: This protects users from stale options and misconfigured alerts/reports after changing schema context.

**Independent Test**: Can be tested by selecting schema A, observing options, switching to schema B, and confirming options update and invalid prior selections are flagged or cleared.

**Acceptance Scenarios**:

1. **Given** the user has selected options from schema A, **When** they switch to schema B, **Then** dropdown options refresh to schema B values.
2. **Given** previously selected values are not present in the new schema, **When** schema changes, **Then** invalid selections are automatically cleared and inline feedback requires reselection before saving.

---

### User Story 3 - Handle Missing or Empty Schema Safely (Priority: P3)

As a builder user, I need clear feedback when schema data is unavailable so I understand why dropdown options are missing and what to do next.

**Why this priority**: This reduces confusion and support friction in degraded or incomplete data states.

**Independent Test**: Can be tested by loading a builder state with missing/empty schema data and confirming disabled dropdowns plus a clear message are shown.

**Acceptance Scenarios**:

1. **Given** schema data is unavailable, **When** the user opens alert or report builder, **Then** schema-driven dropdowns are disabled and a clear explanatory message is displayed.
2. **Given** schema data exists but has no valid selectable fields, **When** the user attempts to configure a dropdown-based field, **Then** they are informed no options are available and cannot save invalid configuration.

### Edge Cases

- A schema contains duplicate display labels for different fields; dropdowns must still allow unambiguous selection.
- A schema update removes a previously selected field after the form is partially completed.
- A schema contains many options; users must still locate and select an intended value without timing out or freezing.
- Alert and report builders reference different schema versions in the same session.
- User loses permission to the active schema during an in-progress builder session.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST generate alert builder dropdown options directly from the currently selected schema.
- **FR-002**: System MUST generate report builder dropdown options directly from the currently selected schema.
- **FR-003**: System MUST prevent users from selecting or saving values not present in the active schema.
- **FR-004**: System MUST refresh dropdown options when schema context changes within a builder session.
- **FR-005**: System MUST detect invalid prior selections after a schema change, automatically clear those selections, and require user correction before save through inline feedback.
- **FR-006**: System MUST provide clear empty-state messaging when schema data is missing, unreadable, or contains no selectable options.
- **FR-007**: System MUST apply consistent option naming and ordering rules across alert and report builders for the same schema.
- **FR-008**: System MUST preserve valid user selections during non-schema form edits in the same session.
- **FR-009**: System MUST record validation failures caused by schema-option mismatch in user-visible form feedback.
- **FR-010**: System MUST treat alert builder and report builder schema version selection independently, based on each builder's explicitly selected schema version.
- **FR-011**: System MUST load and render schema-derived dropdown options within 2 seconds after schema selection for typical builder workloads.
- **FR-012**: System MUST clear schema-derived options, block save, and display an authorization message when schema access is lost during an active editing session.
- **FR-013**: System MUST expose schema-reference and schema-option retrieval endpoints for builder dropdown population.
- **FR-014**: System MUST expose a builder-selection validation endpoint that returns blocking validation issues and cleared slot IDs.

### Key Entities *(include if feature involves data)*

- **Schema Definition**: A structured source of selectable fields used to build alert/report dropdown options.
- **Dropdown Option**: A selectable value derived from schema metadata and presented in alert/report builder forms.
- **Builder Configuration**: User-authored alert or report settings that include selected schema-derived dropdown values.
- **Validation State**: The form status that indicates whether current selections are valid for the active schema.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 95% of users can configure required dropdown fields for a new alert in under 90 seconds.
- **SC-002**: 95% of users can configure required dropdown fields for a new report in under 90 seconds.
- **SC-003**: Invalid saved configurations caused by schema-field mismatch are reduced by at least 80% versus pre-feature baseline.
- **SC-004**: At least 90% of users complete first-attempt configuration without needing to manually correct typed field names.
- **SC-005**: Support requests related to "missing/invalid builder field options" decrease by at least 40% within one release cycle.
- **SC-006**: 95% of schema selection events display populated dropdown options within 2 seconds.

## Assumptions

- "Stary script schemas" refers to an existing schema source already used by the product domain.
- Alert builder and report builder both require schema-derived field selection as part of normal configuration.
- Users have permission to access schemas relevant to their builder context.
- Existing save workflows already block submission when required fields are unresolved.
