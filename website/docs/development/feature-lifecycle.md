# Feature lifecycle

Each feature uses an immutable lowercase slug shared by its documentation directory and branch, for example
`website/docs/features/first-capability/` and `feat/first-capability`. Beads tracks the work; the feature directory holds
the design before implementation and the delivery record afterwards.

## Responsibilities

```text
Beads                                 executable state, dependencies, and delivery history
website/docs/features/<slug>/design.md    intended feature behavior and design
reader-facing docs under website/docs/    current supported behavior
code and tests                        implementation evidence
website/docs/features/<slug>/index.md     delivered capability and design reconciliation
```

## Feature records

`design.md` records the intended behavior, boundaries, decisions, validation strategy, documentation impact, and task
decomposition before implementation starts. `index.md` is written at delivery and describes what the feature provides
and how it differs from its design. Both start from `website/docs/features/_template/`.

Only delivered work is published. The site build excludes a feature directory until its `index.md` exists, so a design
can be committed and reviewed before delivery without appearing on the site. Adding `index.md` publishes both records
and lists the feature under Implemented Features automatically.

Feature records hold durable information only. They link the design and list the tests that cover the feature, but
never pull requests, commits, branch names, delivery status, review notes, or validation run results; Beads and Git
history own that state. The link runs one way: the Beads feature root stores the slug and design path, so the
published records carry no Beads IDs.
