# Agent Workflows

This repository includes native OpenCode workflow commands under:

- `.opencode/commands/`

Available OpenCode commands:

- `/plan-features`
- `/start-feature`
- `/review-feature-spec`
- `/implement-feature`
- `/close-feature`
- `/project-alignment-review`
- `/project-alignment-execute`
- `/project-alignment-land`

## Intent

These command files execute the repository workflow consistently.

They assume the native OpenCode runtime for execution, including runtime tools
such as `task` when a command explicitly requires a second-agent review step.

The repository policy still lives in:

- `docs/src/development.md`
- `docs/src/features/index.md`
- `AGENTS.md`

## Workflow Roles

`/plan-features` is for creating, refining, and inspecting the planned feature roadmap.

`/start-feature` is for opening a feature branch with initial `design.md` and
`tasks.md`.

`/review-feature-spec` is for checking whether a feature spec is
implementation-ready.

`/implement-feature` is for executing the feature tasks.

`/close-feature` is for reconciling delivered implementation with the docs.

`/project-alignment-review`, `/project-alignment-execute`, and
`/project-alignment-land` are the deterministic repository-wide alignment
pipeline.

## Workflow Mapping

Recommended sequence:

1. Use `/plan-features` to create or inspect the planned feature roadmap.
2. Use `/start-feature` when creating a feature.
3. Use `/review-feature-spec` before major implementation work.
4. Use `/implement-feature` to execute the feature tasks.
5. Use `/close-feature` before opening or finalizing the pull request.
6. Use `/project-alignment-review`, `/project-alignment-execute`, and
   `/project-alignment-land` when you want the repository-wide deterministic
   alignment pipeline.

## Enforcement Boundary

`hk` hooks enforce structural repository rules.

The command files help with consistency, but they do not replace human review
after the initial release when pull requests are required.
