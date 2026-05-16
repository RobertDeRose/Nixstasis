# Report View Improvements

## Feature Name

`report-view-improvements`

## Goal

Make custom report list and detail pages easier to scan, filter, navigate, and
reuse.

## Users

- Report consumers reviewing generated results.
- Operators managing saved custom reports.

## Requirements

- Separate report metadata, controls, results, and status messaging.
- Support column sorting and per-column filtering.
- Support clearing active filters and sort state.
- Preserve report view state during an active session.
- Support saved report view preferences when available.
- Fall back safely when saved preferences no longer match report structure.
- Respect report field permissions in every view state.
- Provide useful empty and error states.
- Provide explicit View, Edit, and Delete actions in the custom report list.
- Require explicit confirmation before deleting a custom report.
- Support numeric filter operators `gt`, `gte`, `eq`, `lte`, `lt` and string operators `contains`, `not_contains`, `is`, `is_not`.

## Proposed Design

Report view improvements refine the existing reporting LiveViews and reporting
context rather than introducing a new reporting model. Filter and sorting
semantics belong in reporting module docs when they are current API behavior.

## Validation

- Large reports remain scannable with stable headers/controls.
- Filtering and sorting update predictably.
- Invalid saved preferences fall back with a user-visible message.
- Delete requires confirmation.
