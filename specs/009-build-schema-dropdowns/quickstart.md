# Quickstart: Schema-Driven Builder Dropdowns

## Goal

Validate that alert and report builders use schema-driven dropdown options with independent schema-version behavior,
automatic invalid-selection clearing, permission-loss handling, and <=2s option-load performance.

## Prerequisites

- Run from repo root: `.`
- Server app dependencies available for `packages/server`
- At least two schemas available for test user:
  - `schema-A` with field `temperature`
  - `schema-B` without field `temperature`

## 1) Start server test loop

```bash
cd packages/server
mix test
```

Expected:
- Existing tests pass.
- New feature tests cover schema option loading, invalidation, and authorization-loss behavior.

## 2) Verify alert builder dropdown loading

1. Open Alerts page and start Add Rule flow.
2. Select `schema-A`.
3. Open condition field dropdown.

Expected:
- Dropdown is populated from schema-derived options only.
- Options appear within 2 seconds for normal schema sizes.

## 3) Verify report builder dropdown loading

1. Open Reports page and start Create Report flow.
2. Select `schema-A`.
3. Add a column and filter.
4. Open field/path dropdowns.

Expected:
- Column/filter field dropdowns are populated from schema-derived options only.
- Option naming/order is consistent with alert builder for the same schema.

## 4) Verify schema-change invalidation behavior

1. In either builder, select `temperature` from `schema-A`.
2. Switch to `schema-B`.

Expected:
- Previously selected invalid values are automatically cleared.
- Inline feedback indicates reselection is required.
- Save remains blocked until valid selections are restored.

## 5) Verify independent schema versions per builder

1. In alert builder, select version `v1` of a schema.
2. In report builder, select version `v2` of the same schema.

Expected:
- Each builder retains and uses its own selected schema version.
- Changing version in one builder does not alter selections in the other builder.

## 6) Verify permission-loss fail-closed behavior

1. Begin editing with a schema the user can access.
2. Revoke access (or simulate authorization failure).
3. Trigger option refresh.

Expected:
- Schema-derived dropdown options clear.
- Save is blocked.
- Authorization message is shown until access is restored.

## 7) Performance check

Track time from schema selection event to populated dropdown render.

Expected:
- 95% of observed interactions are <=2 seconds.

## 8) Completion-time metrics check (SC-001 / SC-002)

1. Run 20 timed alert-builder configuration attempts (new rule flow).
2. Run 20 timed report-builder configuration attempts (new report flow).
3. Record median and 95th percentile completion time.

Expected:
- Alert-builder completion time is <=90 seconds for at least 95% of attempts.
- Report-builder completion time is <=90 seconds for at least 95% of attempts.

## 9) Outcome baseline and post-release validation (SC-003 / SC-004 / SC-005)

### Baseline capture (pre-release)

- Capture invalid-save attempt rate from `[:nixstasis, :builder, :invalid_save_attempt]`.
- Capture first-attempt success rate from `[:nixstasis, :builder, :first_attempt_success]` and total save attempts.
- Capture support-ticket count for issues tagged `missing/invalid builder field options`.

### Post-release review window

- Compare invalid-save attempt rate to baseline.
- Compare first-attempt completion rate to baseline.
- Compare support-ticket count to baseline.

### Release checklist

- [ ] Invalid save configurations reduced by >=80% versus baseline.
- [ ] First-attempt completion rate reached >=90%.
- [ ] Support requests for missing/invalid builder options reduced by >=40%.
