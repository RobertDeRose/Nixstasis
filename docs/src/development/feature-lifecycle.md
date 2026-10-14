# Feature lifecycle

Each feature uses an immutable lowercase slug shared by its documentation directory and branch, for example
`docs/src/features/first-capability/` and `feat/first-capability`. Beads tracks the work; the feature directory holds
the design before implementation and the delivery record afterwards.

## Responsibilities

```text
Beads                                 executable state, dependencies, and delivery history
docs/src/features/<slug>/design.md    intended feature behavior and design
reader-facing docs under docs/src/    current supported behavior
code and tests                        implementation evidence
docs/src/features/<slug>/index.md     delivered capability and design reconciliation
```

## Feature records

`design.md` records the intended behavior, boundaries, decisions, validation strategy, documentation impact, and task
decomposition before implementation starts. `index.md` is written at delivery and describes what the feature provides
and how it differs from its design. Both start from `docs/src/features/_template/`.

Feature records hold durable information only. They link the Beads feature root and the design, and list the tests that
cover the feature, but never pull requests, commits, branch names, delivery status, review notes, or validation run
results; Beads and Git history own that state.
