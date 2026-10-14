# Feature lifecycle

Each feature uses an immutable lowercase slug shared by its documentation directory and branch, for example
`docs/src/features/first-capability/` and `feat/first-capability`. Beads tracks the work; the feature directory holds
the design before implementation and the delivery record afterwards.

## Responsibilities

```text
Beads                                            executable state and dependencies
docs/src/features/<slug>/design.md         intended feature behavior and design
reader-facing docs under docs/src/               current supported behavior
code and tests                                   implementation evidence
docs/src/features/<slug>/index.md          delivered reconciliation and audit record
```

## Feature records

`design.md` records the intended behavior, boundaries, decisions, validation strategy, documentation impact, and task
decomposition before implementation starts. `index.md` is written at delivery and reconciles what shipped against the
design and the reader-facing pages. `mise run docs:check` runs `scripts/check-docs.py`, which requires the current
heading structure in both files.

## Historical design exemptions

The following delivered features retain their earlier design headings as historical intent. Their `index.md`
implemented records, closed Beads epics, and reader-facing pages remain the current delivery authority:

- `docs/src/features/authcrunch-role-contract/design.md`
- `docs/src/features/compose-dev-harness/design.md`
- `docs/src/features/dashboard-home/design.md`
- `docs/src/features/device-detail-page/design.md`
- `docs/src/features/go-client-rewrite/design.md`
- `docs/src/features/iot-device-monitoring/design.md`
- `docs/src/features/packaging-deployment-migration/design.md`
- `docs/src/features/phoenix-ui-polish/design.md`
- `docs/src/features/production-operations-runbooks/design.md`
- `docs/src/features/report-view-improvements/design.md`
- `docs/src/features/rich-api-examples/design.md`
- `docs/src/features/self-extracting-installer/design.md`
- `docs/src/features/server-client-e2e-tests/design.md`
- `docs/src/features/server-command-allowlist-management/design.md`
- `docs/src/features/server-provided-frps-token/design.md`
- `docs/src/features/starlark-script-system/design.md`

`scripts/check-docs.py` exempts only these exact paths from current design-heading completeness checks. New and reopened
features must use the current design structure; this exemption does not apply to their designs.
