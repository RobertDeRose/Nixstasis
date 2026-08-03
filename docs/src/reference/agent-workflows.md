# Agent Workflows

This repository uses the dstack workflow skills for planning, implementation,
review, documentation reconciliation, and delivery. The command definitions
are provided by the installed dstack skills rather than embedded in the
repository.

## Installing dstack skills

Install or refresh the skills with:

```bash
npx --yes skills@1.5.16 add RobertDeRose/dstack
npx skills update
```

## Feature workflow

Use the following commands for feature work:

1. `/plan-features <idea>` creates feature designs, documentation structure,
   and the Beads dependency graph.
2. `/start-feature <slug>` activates and reviews a planned feature.
3. `/implement-feature <slug>` implements the next ready feature task.
4. `/close-feature <slug>` reconciles documentation, validates delivery, and
   prepares the requested delivery action.

Use `/implement-task <exact Beads ID or title>` for one standalone task outside
a `workflow:feature` epic.

## Project maintenance

- `/setup-project` initializes a new dstack-managed project.
- `/update-project` updates the project scaffold or routes legacy workflow
  migration.
- `/audit-project` reconciles Beads, designs, documentation, code, tests, and
  migration state.

## Sources of truth

- **Beads** owns executable work state, dependencies, priorities, claims,
  findings, and evidence.
- `docs/src/features/<slug>/design.md` owns intended feature behavior,
  boundaries, decisions, validation, and documentation impact.
- Reader-facing pages under `docs/src/` own current supported behavior.
- `docs/src/features/<slug>/index.md` owns delivered-feature reconciliation
  and audit history.
- Code and tests provide implementation evidence.

Use Beads instead of ad hoc Markdown task lists for executable work. Use
`bd remember` for durable cross-feature knowledge.

## Enforcement boundary

Repository policy lives in `AGENTS.md` and the dstack workflow documentation.
The skills coordinate the workflow, while code, tests, and documentation remain
the authoritative evidence for implementation and supported behavior.
