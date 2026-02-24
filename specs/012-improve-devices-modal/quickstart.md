# Quickstart: Devices Page and Device Modal Improvements

## Prerequisites
- Start server app from `packages/server`.
- Seed or use data with varied Product, Account Number, and Status values.
- Ensure modal dependencies from spec 005 are operational (PCP data source and terminal channel path).

## Validation Flow

1. Open Devices page.
2. Confirm list headers include `MAC Address` and `Product`.
3. Click a Product value in a row.
4. Verify Product filter activates and list narrows.
5. Click a Status value in any remaining row.
6. Verify Status filter is added (AND behavior), not replacing Product filter.
7. Click an Account Number value.
8. Verify third filter is added and list narrows further.
9. Remove one active filter chip.
10. Verify only that filter is removed and remaining filters persist.
11. Click `Clear all`.
12. Verify full list is restored and all chips clear.
13. Click a `MAC Address` link.
14. Verify device modal opens for that device.
15. In modal, verify PCP data view renders and terminal tab initializes.
16. Close modal.
17. Verify return to same list context (filters and scroll position preserved).
18. Capture modal-open latency for repeated runs and verify p95 is <= 2 seconds.
19. Validate desktop and mobile viewport behavior for filter chips and table interactions.

## Post-Release Measurement (SC-004)

1. Track support tickets tagged "cannot find device details" for one baseline release cycle.
2. After rollout, track the same ticket tag for one equivalent release cycle.
3. Calculate percentage change and confirm at least 30% reduction.
4. If reduction is below target, review telemetry events for discovery and modal-open failures.

## Expected Outcomes
- Additive multi-column filtering works for Product, Account Number, and Status.
- Filters are removable individually and via `Clear all`.
- MAC Address link reliably opens existing spec-005 modal experience.
- PCP and terminal interactions remain functional from this entrypoint.
- Modal-open performance meets p95 <= 2s target in validation runs.
- Support-ticket trend demonstrates the targeted reduction after release.
