# Feature Specification: Polish Phoenix UI

**Feature Branch**: `003-polish-phoenix-ui` **Created**: Sun Feb 01 2026 **Status**: Draft **Input**: User description: "The Phoenix application inside `packages/nixstasis/server` needs to look professional and polished"

## Clarifications

### Session 2026-02-01

- Q: Theme strategy? → A: System-Aware Manual Toggle (Tailwind `selector` strategy).
- Q: Navigation Layout? → A: Vertical Sidebar (Collapsible).
- Q: Mobile Navigation Strategy? → A: Bottom Navigation Bar (move primary items to bottom bar on mobile).
- Q: Data Display Style? → A: Minimal/Flat (Data-First) table style.
- Q: Notification Style? → A: Toast Notifications (Floating).

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.
-->

### User Story 1 - Consistent Application Layout (Priority: P1)

As a user, I want to navigate a clean, structured application layout featuring a collapsible vertical sidebar so that I can easily find information without visual distraction.

**Why this priority**: A professional application requires a solid foundation. The layout (header, sidebar, main content area) sets the stage for all other interactions.

**Independent Test**: Can be fully tested by navigating to all main pages and verifying the sidebar consistency and collapse functionality.

**Acceptance Scenarios**:

1. **Given** I am on any page of the application, **When** I view the layout, **Then** I see the logo and vertical navigation sidebar aligned correctly.
2. **Given** I am on a desktop screen, **When** I view the content area, **Then** it is centered with appropriate maximum width and does not stretch comfortably across the entire screen.
3. **Given** I am on a mobile device, **When** I view the layout, **Then** the sidebar is hidden, and primary navigation items appear in a fixed bottom navigation bar without horizontal scrolling.

---

### User Story 2 - Professional Typography & Spacing (Priority: P2)

As a user, I want to read content that is legible and well-spaced so that I can process information efficiently without eye strain.

**Why this priority**: "Polished" largely comes down to typography and whitespace. Good vertical rhythm and readable font sizes are essential for a professional look.

**Independent Test**: Can be tested by viewing pages with text content (dashboards, lists) and verifying font hierarchy and spacing consistency.

**Acceptance Scenarios**:

1. **Given** I am viewing a page with headings and body text, **When** I compare them, **Then** there is a clear visual hierarchy (H1 > H2 > H3) using size and weight.
2. **Given** I am viewing a list or table, **When** I look at the items, **Then** there is consistent padding between rows and elements, preventing a cluttered appearance.
3. **Given** I am reading text, **When** I check the contrast, **Then** the text color against the background meets WCAG AA standards for accessibility.

---

### User Story 3 - Interactive & Responsive Components (Priority: P3)

As a user, I want to interact with UI elements (buttons, forms, cards) that provide clear visual feedback so that I know my actions are recognized.

**Why this priority**: Micro-interactions and state visibility (hover, focus) are the hallmarks of a "polished" application.

**Independent Test**: Can be tested by interacting with buttons, links, and form inputs throughout the application.

**Acceptance Scenarios**:

1. **Given** I see a button or link, **When** I hover over it with my mouse, **Then** the visual style changes (color shift, underline, shadow) to indicate interactivity.
2. **Given** I am using a keyboard to navigate, **When** I focus on a form input or button, **Then** a clear focus ring is visible.
3. **Given** I am viewing a card or container, **When** I view it on a small screen, **Then** its internal padding remains appropriate and content does not overflow.

---

### Edge Cases

- **Mobile Landscape**: What happens when the device is rotated to landscape? The layout should adjust to use the available width without breaking the navigation.
- **Very Long Content**: How does the system handle very long headings or table cell content? Text should wrap or truncate with an ellipsis, not overflow the container.
- **Zoom Levels**: How does the layout handle 200% browser zoom? The layout should remain usable without horizontal scrolling (reflow).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST use a consistent color palette derived from the application's design system for all UI elements.
- **FR-002**: System MUST implement a global layout template that includes a responsive header and collapsible vertical sidebar navigation (desktop).
- **FR-003**: All text content MUST use a standardized type scale to ensure hierarchy.
- **FR-004**: Interactive elements (Buttons, Links, Inputs) MUST have defined states for `default`, `hover`, `focus`, and `active`.
- **FR-005**: Main content containers MUST use responsive max-widths to preventing stretching on large screens.
- **FR-006**: Form inputs MUST have consistent styling (border, padding, rounded corners) that matches the application's theme.
- **FR-007**: Tables and Lists MUST use consistent cell padding and border/separator styles (Minimal/Flat style), avoiding card layouts for dense data.
- **FR-008**: System MUST implement a manual theme toggle that respects system preferences by default (Tailwind `selector` strategy).
- **FR-009**: System MUST persist the user's manual theme choice (Light/Dark) across sessions (e.g., local storage or cookie).
- **FR-010**: System MUST adapt navigation for mobile viewports by converting the sidebar into a fixed Bottom Navigation Bar.
- **FR-011**: System MUST render application flash messages (info, error) as floating "Toast" style notifications (top-right) instead of static banners.

### Key Entities *(include if feature involves data)*

- **Theme**: The collection of design tokens (colors, spacing, typography) defined in the CSS framework.
- **Layout**: The master template wrapping all pages.
- **Components**: Reusable UI blocks (Buttons, Cards, Inputs).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All pages pass a WCAG AA contrast check for main text content.
- **SC-002**: Zero instances of horizontal scrolling on viewport widths of 375px (mobile) and above.
- **SC-003**: 100% of clickable elements (buttons, links) exhibit a visible change on hover and focus.
- **SC-004**: Navigation remains fully accessible and functional on both mobile (< 640px) and desktop viewports.
