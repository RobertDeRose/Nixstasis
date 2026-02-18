# Feature Specification: Add Rule Modal Improvements

**Feature Branch**: `011-add-rule-modal-improvements` **Created**: 2026-02-16 **Status**: Draft **Input**: User description: "improve \"Add Rule\" modal to match the improvements made to \"Create Report\" modal"

## Clarifications

### Session 2026-02-16

- Q: In Add Rule edit mode, which fields should be non-editable? → A: Only rule name is immutable in edit mode.
- Q: What keyboard submit behavior should Add Rule enforce inside the modal? → A: Support Ctrl+Enter/Cmd+Enter for save; plain Enter does not force modal submit from text fields.
- Q: If a user has unsaved changes in Add Rule and presses Escape/cancel, what should happen? → A: Prompt for confirmation only when unsaved changes exist.
- Q: What accessibility validation target should this feature require? → A: Meet WCAG 2.1 AA expectations for modal interaction and form feedback.
- Q: After save success/failure in Add Rule modal, what message behavior should be required? → A: Success auto-dismisses; error persists until user action.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Efficient Rule Creation Flow (Priority: P1)

As a user creating an alert rule, I can complete rule setup in a modal flow that matches the structure, clarity, and interaction quality of the Create Report modal.

**Why this priority**: Rule creation is a core workflow. Friction in this modal directly slows configuration and increases setup errors.

**Independent Test**: Open Add Rule, complete a valid rule from start to finish, and confirm the rule is created without needing workaround steps or additional screens.

**Acceptance Scenarios**:

1. **Given** a user opens Add Rule, **When** the modal renders, **Then** the modal layout, sectioning, and interaction model align with the Create Report modal patterns.
2. **Given** required inputs are completed with valid values, **When** the user saves, **Then** the rule is created and the modal exits with a clear success result.

---

### User Story 2 - Predictable Keyboard and Focus Behavior (Priority: P2)

As a keyboard user, I can navigate and complete Add Rule with consistent focus, escape, and submit behavior matching Create Report.

**Why this priority**: Consistent keyboard behavior reduces cognitive load and prevents errors for frequent and accessibility-focused users.

**Independent Test**: Use keyboard-only navigation to open Add Rule, move through controls, cancel with Escape, and submit via keyboard shortcut/submit action.

**Acceptance Scenarios**:

1. **Given** the modal is open, **When** the user navigates with keyboard, **Then** focus order is logical, visible, and stays within the modal.
2. **Given** focus is inside a text/select input, **When** Escape is pressed, **Then** the modal closes through the standard cancel path.

---

### User Story 3 - Safer Validation and Error Recovery (Priority: P3)

As a user editing inputs in Add Rule, I get clear validation and can recover from errors without losing progress.

**Why this priority**: Good validation and recovery reduce failed saves and frustration, especially during complex rule definitions.

**Independent Test**: Trigger validation errors intentionally, correct them inline, and complete save without reopening the modal or re-entering unchanged values.

**Acceptance Scenarios**:

1. **Given** one or more invalid values, **When** save is attempted, **Then** the modal remains open and shows actionable validation guidance.
2. **Given** validation errors were shown, **When** the user corrects values, **Then** errors clear appropriately and save becomes available.

### Edge Cases

- User opens Add Rule with no available selectable schema fields: modal should provide clear guidance and block save.
- User toggles between values that change operator/value validity: invalid combinations should be prevented or clearly flagged before save.
- User cancels after entering partial data: modal closes without creating or modifying a rule.
- User quickly submits multiple times: only one create action should be processed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Add Rule modal MUST match Create Report modal parity for section hierarchy/order, primary and secondary action placement, inline validation/error placement, initial focus target behavior, and cancel/close affordance placement.
- **FR-002**: The Add Rule modal MUST preserve a single primary completion action and a clear cancel path, with action availability tied to validation state.
- **FR-003**: The system MUST provide inline validation feedback for invalid rule input and MUST prevent save while required inputs are invalid or incomplete.
- **FR-004**: Keyboard interactions in Add Rule MUST match the Create Report modal behavior for focus management and Escape-to-close behavior.
- **FR-005**: Focus on modal open MUST land on the first actionable rule-building control so users can begin immediately without manual pointer interaction.
- **FR-006**: Editing within Add Rule MUST not cause unrelated validation failures (for example, unchanged identifying values should not be treated as duplicates).
- **FR-007**: Add Rule MUST retain user-entered values while validation errors are being corrected.
- **FR-008**: The modal MUST communicate success and failure outcomes clearly, including non-destructive recovery for failed save attempts.
- **FR-009**: Add Rule behavior MUST remain consistent between create and edit contexts, with only context-appropriate differences.
- **FR-010**: In edit mode, only the rule name MUST be immutable; all other editable rule settings remain modifiable, subject to validation.
- **FR-011**: The modal MUST support `Ctrl+Enter` / `Cmd+Enter` as the keyboard save shortcut, and plain Enter in text-entry contexts MUST NOT force full modal submission.
- **FR-012**: When unsaved changes exist, cancel/Escape MUST show a confirmation step before closing; when no unsaved changes exist, cancel/Escape MUST close immediately.
- **FR-013**: Add Rule modal interaction and form feedback MUST satisfy WCAG 2.1 AA expectations for keyboard operation, focus visibility, label association, and error announcement behavior.
- **FR-014**: On save outcomes, success feedback MUST auto-dismiss after 3 seconds (±1 second tolerance), while error feedback MUST persist until explicit user dismissal or correction action.

### Key Entities *(include if feature involves data)*

- **Alert Rule Draft State**: The in-progress set of user-entered modal values, validation state, and save eligibility.
- **Rule Definition**: The persisted configuration created or updated from modal input, including conditions and metadata required for rule execution.
- **Validation Issue**: A user-facing error/warning tied to one or more rule inputs that affects save readiness.

## Assumptions

- “Match improvements” means parity with current Create Report modal behavior for structure, keyboard handling, and validation UX patterns.
- Existing Add Rule data model and business logic remain in scope; this feature focuses on modal UX and interaction quality, not new rule semantics.
- Users who can open Add Rule already have permission to create or edit rules.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete a valid Add Rule flow in 2 minutes or less for common rule configurations.
- **SC-002**: At least 90% of first-attempt saves from Add Rule succeed without reopening the modal.
- **SC-003**: Keyboard-only users can complete the full Add Rule create flow with no pointer interaction and no blocked focus transitions.
- **SC-004**: Validation-related failed save attempts for Add Rule decrease by at least 40% compared with baseline behavior before this feature.
- **SC-005**: Accessibility verification for the Add Rule modal passes WCAG 2.1 AA checks for modal dialogs and form validation feedback in the project’s acceptance test process.
