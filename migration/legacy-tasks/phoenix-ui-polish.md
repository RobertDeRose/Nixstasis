# Tasks: Phoenix UI Polish

**Input**: Feature design and current Phoenix UI docs.

## Phase 1: Setup

- [x] T001 Verify project compiles and runs cleanly before starting `packages/server`
- [x] T002 Verify Tailwind/DaisyUI configuration in `packages/server/assets/css/app.css`

## Phase 2: Foundational (Layout & Core Components)

- [x] T003 Update `core_components.ex` to use DaisyUI standard table classes in `packages/server/lib/nixstasis_web/components/core_components.ex`
- [x] T004 Update `core_components.ex` to use DaisyUI standard button classes in `packages/server/lib/nixstasis_web/components/core_components.ex`
- [x] T005 Update `core_components.ex` to use DaisyUI standard input classes in `packages/server/lib/nixstasis_web/components/core_components.ex`
- [x] T006 Update `core_components.ex` to use DaisyUI Toast component for flash messages in `packages/server/lib/nixstasis_web/components/core_components.ex`
- [x] T006a Create LiveView test to verify Toast notifications appear in correct position for flash messages in `packages/server/test/nixstasis_web/components/core_components_test.exs`

## Phase 3: User Story 1 - Consistent Application Layout (P1)

- [x] T007 P US1 Create LiveView test for Sidebar layout structure in `packages/server/test/nixstasis_web/controllers/layout_test.exs`
- [x] T008 US1 Implement DaisyUI Drawer structure for responsive Sidebar in `packages/server/lib/nixstasis_web/components/layouts/app.html.heex`
- [x] T009 US1 Create Sidebar component with logo and navigation links in `packages/server/lib/nixstasis_web/components/layouts.ex`
- [x] T010 US1 Implement Bottom Navigation Bar for mobile view in `packages/server/lib/nixstasis_web/components/layouts.ex`
- [x] T011 US1 Integrate Bottom Navigation into `app.html.heex` with conditional mobile visibility in `packages/server/lib/nixstasis_web/components/layouts/app.html.heex`

## Phase 4: User Story 2 - Professional Typography & Spacing (P2)

- [x] T012 P US2 Audit and update existing pages to ensure content containers use responsive max-widths in `packages/server/lib/nixstasis_web/live/`
- [x] T013 US2 Update standard type scale utility classes in `packages/server/assets/css/app.css` (if custom tweaks needed)

## Phase 5: User Story 3 - Interactive & Responsive Components (P3)

- [x] T014 US3 Verify and refine hover/focus states for all `core_components.ex` buttons and links in `packages/server/lib/nixstasis_web/components/core_components.ex`
- [x] T015 US3 Ensure form inputs have consistent border and focus ring styling in `packages/server/lib/nixstasis_web/components/core_components.ex`
- [x] T016 US3 Implement manual theme toggle using DaisyUI `theme-controller` or existing logic in `packages/server/lib/nixstasis_web/components/layouts.ex`
- [x] T016a US3 Create unit test for Theme Controller logic to verify persistence and system preference handling in `packages/server/test/nixstasis_web/controllers/layout_test.exs`

## Phase 6: Polish & Cross-cutting

- [x] T017 Verify all pages pass WCAG AA contrast check
- [x] T018 Verify no horizontal scrolling on mobile viewports
- [x] T019 Final manual verification of layout transition (Desktop <-> Mobile)

## Dependencies

- **US1** requires Foundational Phase to be complete (DaisyUI components ready).
- **US2** builds on the layout established in US1.
- **US3** refines the components implemented in Foundational Phase.

## Parallel Execution

- T003, T004, T005, T006 (Foundational component updates) can be done in parallel.
- T012 (Page audit) can run in parallel with T008-T011 (Layout implementation).
- T007 (Test creation) can run in parallel with T008 (Implementation).

## Implementation Strategy

1. **Foundation**: Update core components first to ensure "atomic" building blocks are polished.
2. **Layout Swap**: Replace the main application layout with the Sidebar/Drawer structure. This is the biggest visual change.
3. **Refinement**: Go through pages and refine typography and spacing (US2) and interaction states (US3).
