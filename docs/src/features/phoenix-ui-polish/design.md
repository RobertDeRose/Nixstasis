# Phoenix UI Polish

## Feature Name

`phoenix-ui-polish`

## Goal

Make the Phoenix application look and feel professional across desktop and
mobile, with consistent layout, typography, responsive navigation, accessible
states, and clear notifications.

## Users

- Operators using the web UI daily.
- Administrators managing devices, alerts, and reports.
- Keyboard and mobile users who need reliable interaction behavior.

## Requirements

- Use a consistent application layout with a responsive header and collapsible desktop sidebar.
- Provide mobile navigation that avoids horizontal scrolling and keeps primary destinations reachable.
- Establish readable typography, spacing, and content max-widths.
- Provide visible hover, focus, active, loading, and error states for interactive controls.
- Use data-first table/list styling for dense data.
- Support a manual light/dark theme toggle that respects system preference by default.
- Persist manual theme choice across sessions.
- Render flash messages as floating toast notifications.
- Preserve WCAG AA contrast and keyboard focus visibility.

## Proposed Design

The UI polish work is a cross-cutting feature over Phoenix layouts, components,
and page templates. The design favors a structured shell, responsive content
areas, consistent form controls, readable tables, and feedback patterns that make
status and errors obvious without distracting from operational data.

## Edge Cases

- Mobile landscape should not break navigation.
- Long headings and table cells should wrap or truncate without layout overflow.
- 200% browser zoom should remain usable without horizontal scrolling.

## Validation

- Verify primary pages at desktop and mobile widths.
- Verify keyboard focus movement and visible focus states.
- Verify main text contrast meets WCAG AA.
- Verify toasts, theme toggle, tables, forms, and navigation use consistent styling.
