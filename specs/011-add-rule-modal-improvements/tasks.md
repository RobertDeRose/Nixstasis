# Tasks: Add Rule Modal Improvements

**Input**: Design documents from `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/`
**Prerequisites**: `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/plan.md`, `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/spec.md`, `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/research.md`, `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/data-model.md`, `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/contracts/add-rule-modal.openapi.yaml`

**Tests**: Tests are MANDATORY for modal interaction logic and save/cancel behavior changes in this feature.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Align task scaffolding and test harness for Add Rule modal parity work.

- [X] T001 Verify Add Rule modal baseline behavior and existing event handlers in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T002 Capture Create Report modal parity references to reuse interaction patterns in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/reports/form_component.ex`
- [X] T003 [P] Prepare/extend shared LiveView test helpers for modal open/edit flows in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/support/live_view_test_helpers.ex`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build reusable modal state/validation plumbing required by all user stories.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 Implement Add Rule draft-state normalization and dirty-tracking helpers in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T005 [P] Add reusable rule form validation mapping and issue shaping for inline feedback in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis/monitoring/alert_rule.ex`
- [X] T006 [P] Add modal feedback state helpers for success auto-dismiss and persistent error behavior in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T007 Wire foundational tests for draft dirty-state and validation retention in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`

**Nixstasis**: Foundation ready; user story implementation can proceed.

---

## Phase 3: User Story 1 - Efficient Rule Creation Flow (Priority: P1) 🎯 MVP

**Goal**: Add Rule modal matches Create Report structure and supports reliable create/edit save flow with clear outcomes.

**Independent Test**: Open Add Rule, create a valid rule, then open edit mode and confirm parity layout, immutable name, and successful save behavior.

### Tests for User Story 1

- [X] T008 [P] [US1] Add LiveView test coverage for Add Rule modal layout/action parity with Create Report in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [X] T009 [P] [US1] Add create-flow save success/error behavior tests (auto-dismiss success, persistent error) in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [X] T010 [P] [US1] Add edit-flow tests ensuring only rule name is immutable while other fields remain editable in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`

### Implementation for User Story 1

- [X] T011 [US1] Refactor Add Rule modal markup/sections/actions to mirror Create Report modal conventions in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T012 [US1] Ensure create-mode submit path enforces validation-gated primary action and single-submit behavior in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T013 [US1] Ensure edit-mode submit path preserves rule identity and allows updating non-name fields in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T014 [US1] Implement post-save outcome messaging behavior (success auto-dismiss, persistent error) in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`

**Nixstasis**: User Story 1 is independently functional and testable.

---

## Phase 4: User Story 2 - Predictable Keyboard and Focus Behavior (Priority: P2)

**Goal**: Keyboard-only users can complete modal interactions with consistent focus, escape handling, and save shortcuts.

**Independent Test**: Operate Add Rule modal with keyboard only, confirm focus trap/visibility, Escape cancel flow, and Ctrl/Cmd+Enter save.

### Tests for User Story 2

- [X] T015 [P] [US2] Add keyboard navigation/focus-order assertions for Add Rule modal in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [X] T016 [P] [US2] Add Escape/cancel behavior tests for pristine vs dirty forms in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [X] T017 [P] [US2] Add keyboard submit tests for Ctrl/Cmd+Enter and non-submitting plain Enter in text inputs in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`

### Implementation for User Story 2

- [X] T018 [US2] Set initial focus on modal open to first actionable rule-building control in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T019 [US2] Implement modal keyboard event handling for Escape through cancel path and dirty confirmation in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T020 [US2] Implement Ctrl/Cmd+Enter save shortcut while preventing unintended plain Enter modal submission in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T021 [P] [US2] Validate current modal keyboard hooks satisfy US2 acceptance criteria and document the result in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/quickstart.md`

**Nixstasis**: User Stories 1 and 2 are both independently functional and testable.

---

## Phase 5: User Story 3 - Safer Validation and Error Recovery (Priority: P3)

**Goal**: Validation issues are actionable, recoverable, and non-destructive during create/edit.

**Independent Test**: Trigger invalid combinations, verify inline issues and blocked save, correct inputs without losing entered values, then save successfully.

### Tests for User Story 3

- [X] T022 [P] [US3] Add validation error rendering/clearing tests with persisted user input state in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [X] T023 [P] [US3] Add no-available-field edge-case tests ensuring guidance and blocked save in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [X] T024 [P] [US3] Add operator/value compatibility transition tests for invalid-to-valid recovery in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`

### Implementation for User Story 3

- [X] T025 [US3] Implement inline validation issue rendering and actionable messaging in Add Rule modal in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T026 [US3] Preserve draft values across failed validation/save attempts and clear issues on corrective edits in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T027 [US3] Handle no-schema-field and invalid operator/value combination edge cases in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- [X] T028 [US3] Ensure validation issue generation and operator/type checks remain consistent with domain expectations in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/lib/nixstasis/monitoring/alert_rule.ex`

**Nixstasis**: All user stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final quality pass across behavior, accessibility, and documentation.

- [X] T029 [P] Execute quickstart validation steps and capture implementation verification notes in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/quickstart.md`
- [X] T030 [P] Add/refresh accessibility-oriented assertions for focus visibility, labels, and error announcement behavior in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server/test/nixstasis_web/live/alerts_live_test.exs`
- [X] T031 Run lint/format/test quality gates for touched server code (`mix format`, `mix credo`, targeted `mix test`) from `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/packages/server`
- [X] T032 Update feature completion notes and dependency confirmation in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/plan.md`
- [X] T033 Define and document baseline measurement method for SC-001, SC-002, and SC-004 in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/quickstart.md`
- [ ] T034 [P] Capture pre-change baseline for validation-related failed save attempts (SC-004) in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/quickstart.md`
- [ ] T035 [P] Execute timed Add Rule flow checks and record results against SC-001 in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/quickstart.md`
- [ ] T036 Execute first-attempt save success sampling and record results against SC-002 in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/quickstart.md`
- [ ] T037 Compare post-change validation-failure rate against baseline and record SC-004 pass/fail in `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/011-add-rule-modal-improvements/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; starts immediately.
- **Foundational (Phase 2)**: Depends on Setup completion; blocks all user stories.
- **User Stories (Phase 3-5)**: Depend on Foundational completion; then execute by priority (P1 → P2 → P3).
- **Polish (Phase 6)**: Depends on completion of targeted user stories.

### User Story Dependencies

- **US1 (P1)**: Starts after Foundational; no dependency on US2/US3.
- **US2 (P2)**: Starts after Foundational; can reuse US1 modal structure but remains independently testable.
- **US3 (P3)**: Starts after Foundational; builds on shared validation plumbing and remains independently testable.

### Within Each User Story

- Tests first (write/confirm failing where applicable).
- Event/state handling before final markup polish.
- Save/cancel behavior before feedback polishing.
- Story completion validated before progressing.

### Parallel Opportunities

- Phase 1: `T003` can run in parallel with `T001-T002` after context review starts.
- Phase 2: `T005` and `T006` can run in parallel after `T004` framing is in place.
- US1 tests `T008-T010` can run in parallel.
- US2 tests `T015-T017` can run in parallel; `T021` can run in parallel with server-side event updates.
- US3 tests `T022-T024` can run in parallel.
- Polish tasks `T029-T030` can run in parallel before final gate `T031-T032`.

---

## Parallel Example: User Story 2

```bash
# Run US2 keyboard/focus test authoring in parallel:
Task: "T015 [US2] Add keyboard navigation/focus-order assertions in alerts_live_test.exs"
Task: "T016 [US2] Add Escape/cancel pristine-vs-dirty tests in alerts_live_test.exs"
Task: "T017 [US2] Add Ctrl/Cmd+Enter and plain Enter behavior tests in alerts_live_test.exs"

# Run implementation split by layer:
Task: "T019 [US2] Server-side Escape/cancel and dirty confirmation flow in index_live.ex"
Task: "T021 [US2] Validate modal keyboard hooks against US2 acceptance criteria in quickstart.md"
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational).
3. Complete Phase 3 (US1).
4. Validate US1 independently via tests and manual modal create/edit checks.

### Incremental Delivery

1. Deliver US1 modal structure and save parity.
2. Add US2 keyboard/focus consistency.
3. Add US3 validation/error recovery hardening.
4. Finish with Phase 6 polish and quality gates.

### Parallel Team Strategy

1. One engineer handles server modal state/events in `index_live.ex`.
2. One engineer handles test expansion in `alerts_live_test.exs`.
3. One engineer handles optional keyboard hook alignment in `assets/js/app.js` and quickstart verification updates.

---

## Notes

- [P] tasks indicate no direct file conflict and minimal dependency coupling.
- [US#] labels provide strict traceability to spec user stories.
- Every user story phase includes independent test criteria and explicit test tasks.
- Keep behavior parity with existing Create Report modal conventions.
