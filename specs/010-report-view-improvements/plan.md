# Implementation Plan: Report View Improvements

**Branch**: `010-report-view-improvements` | **Date**: 2026-02-15 | **Spec**: `specs/010-report-view-improvements/spec.md`
**Input**: Feature specification from `/specs/010-report-view-improvements/spec.md` with additional user scope for sortable/filterable custom-report list and sortable/filterable report results with edit/delete actions.

**Note**: This template is filled in by the `/speckit.plan` command.
See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enhance the Custom Reports list and report detail experience so users can sort by columns, filter by column content, edit report queries via the existing query modal flow, and delete reports through explicit confirmation. The plan adds clear action links (`View`, `Edit`, `Delete`) in each list row, introduces deterministic sort/filter state for both list and results tables, and standardizes filter operators on report results to `>`, `>=`, `==`, `<=`, and `<`.

## Technical Context

**Language/Version**: Elixir 1.19.5, Erlang/OTP 28
**Primary Dependencies**: Phoenix 1.8 LiveView, Ash/AshPhoenix, Ecto
**Storage**: Postgres (existing `custom_reports` + source telemetry tables), LiveView assigns for transient sort/filter state
**Testing**: ExUnit + Phoenix LiveView tests, targeted unit tests for query/filter normalization
**Target Platform**: Phoenix web app (`packages/server`) rendered in modern desktop browsers
**Project Type**: Monorepo web application
**Performance Goals**: 95% of sort/filter interactions update visible table rows in <=1 second for standard dataset sizes
**Constraints**: Preserve existing report builder modal behavior; destructive delete requires explicit user confirmation; report-result filter operators limited to `>`, `>=`, `==`, `<=`, `<`
**Scale/Scope**: Custom Reports index list, report show table, report query modal edit flow, and related reporting context/query builder logic

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Quality & Simplicity: Pass. Scope is constrained to report list/show and reporting context without introducing new subsystems.
- Behavior-Driven API Testing: Pass. LiveView tests will assert Given/When/Then sorting, filtering, edit, and confirmed delete behaviors.
- Targeted Unit Testing: Pass. Query normalization and comparator coercion will receive focused unit coverage.
- User Experience First: Pass. Action links become explicit and discoverable; delete has clear confirmation; sorting/filtering reduces scanning time.
- Branding: Pass. Action links and modal confirmation use existing DaisyUI/Tailwind style conventions and existing report page patterns.
- Performance Compliance: Pass. Interaction latency target defined and verified in quickstart.

**Post-Design Check (after Phase 1)**: Pass. Design artifacts preserve UX-first behavior, testing obligations, and explicit performance constraints.

## Project Structure

### Documentation (this feature)

```text
specs/010-report-view-improvements/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
packages/
└── server/
    ├── lib/
    │   ├── nixstasis/
    │   │   ├── reporting.ex
    │   │   └── reporting/
    │   │       ├── custom_report.ex
    │   │       └── query_builder.ex
    │   └── nixstasis_web/
    │       ├── components/
    │       └── live/
    │           └── reports/
    │               ├── index_live.ex
    │               ├── form_component.ex
    │               └── show_live.ex
    └── test/
        ├── nixstasis/
        └── nixstasis_web/
            └── live/
                └── reports_live_test.exs
```

**Structure Decision**: Implement feature behavior in existing reports LiveViews. Keep persistence and query semantics in `Nixstasis.Reporting` and `Nixstasis.Reporting.QueryBuilder`. Extend `reports_live_test.exs` and add focused context-level tests under `packages/server/test/nixstasis/reporting` as needed.

## Baseline Metrics Queries

- Report open-to-first-insight time: median time from report detail page load to first successful sort/filter application.
- Report maintenance completion time: median time to edit query and save from Custom Reports list.
- Report table interaction errors: count of validation or malformed filter submissions per release window.

## Implementation Notes

- Preserve existing `View` link behavior while adding explicit `Edit` and `Delete` action links in each list row.
- Use shared comparator mapping for list/report filtering to avoid divergent semantics.
- Confirmation modal must include report name and non-ambiguous irreversible-action language.
- The OpenAPI contract in `contracts/custom-reports-view.openapi.yaml` is reference-only for this increment; implementation remains LiveView-first in this feature scope.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| None | N/A | N/A |
