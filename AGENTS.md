# AGENTS

Start here when working in this repository.

## Repository map

- `website/docs/repository-structure.md` maps every package and top-level path; `website/docs/modules/` describes each
  module's architecture.
- `packages/server/AGENTS.md` and `packages/client/AGENTS.md` hold package-specific commands and conventions.
- `packages/caddy` and `packages/frp` build the gateway images; `uv run packages/frp/bin/test_frps_render_config.py`
  tests the FRPS config renderer.
- Run repository validation with `mise run check` and deterministic fixes with `mise run fix`.

## Ground Rules

- Prefer the smallest correct change.
- All code should follow the principles of DRY, KISS, and YAGNI, and be designed with good separation of concerns.
- Keep documentation and implementation aligned in the same unit of work.
- Keep docs durable. Never record transient or variable state in docs: PR numbers or links, commit SHAs, branch
  names, review-pass notes, delivery or merge status, or validation run results. Beads (or Git history) owns that
  state. When editing a doc that already contains such state, remove it rather than updating it.
- Do not treat a task as complete if the code and docs-driven feature docs disagree.
- Nixstasis has no stability guarantee before `v1.0.0`. Any pre-1.0 release may break the client-server API,
  configuration, client state files, and database contents; affected servers and devices are redeployed and
  re-enrolled, not upgraded in place. Make breaking changes directly: add no data migrations for old state, legacy
  aliases, compatibility shims, or deprecation periods. Ash schema migrations are still committed as described
  below. Reviewers must not flag missing backward compatibility or upgrade paths as defects.

## Ash Codegen

- For `packages/server`, treat `mix ash.codegen --dev` output as temporary
  local iteration state.
- Before committing Ash resource changes, run `mix ash.codegen <descriptive_name>`.
- Commit named Ash migrations and named resource snapshots.
- Do not commit `*_dev.exs` migrations or `*_dev.json` resource snapshots.
- Prefer `mix ash.codegen --check` in verification steps when Ash resources change.

## Commit Guidance

- Use Conventional Commits.
- Follow the Conventional Commits 1.0.0 shape: `<type>[optional scope]: <description>`.
- The repo-local `hk` `commit-msg` hook enforces the conventional format and line-length limits configured in `package.json`.

### Supported Scopes

- Prefer one of these scopes when a commit is primarily about a single area:
  - `client`
  - `server`
  - `shared`
  - `caddy`
  - `frp`
  - `deploy`
  - `ci`
  - `docs`
  - `tooling`
  - `repo`
- Keep scopes as narrow as possible.
- Prefer separate commits per package or concern when the work can be split cleanly.
- Use `repo` for rare, truly cross-cutting changes that must land together.
- For cross-cutting commits, use the body to explain why the change spans multiple areas and what parts moved together.

### Subject

- Keep the subject clear first, short second.
- Keep the subject within the enforced `commitlint` limit.

### Body

- For nontrivial changes, include a body.
- Use the body to explain why the change exists and summarize the important parts.
- Keep body lines within the enforced `commitlint` limit.

### Multiline Input

- Prefer stdin heredocs for multiline command input when the tool supports it, such as `-F -` or `--file -`.
- Example:
  - `git commit -F - <<'EOF'`
- Use process substitution only when the command requires a real file path.
- Prefer this to reduce quoting and spacing mistakes in commit messages and other structured text.

### Allowed Types

- `build`
- `chore`
- `ci`
- `docs`
- `feat`
- `fix`
- `perf`
- `refactor`
- `revert`
- `style`
- `test`

Reference:

- `https://www.conventionalcommits.org/en/v1.0.0/`

## Work tracking

Check ready work before selecting a task:

```bash
bd ready --json
```

Inspect selected work with `bd show <id> --json` and read structured metadata before prose.

### Sources of truth

- **Beads** owns executable work state, dependencies, priorities, claims, findings, evidence, and delivery history
  (PRs, commits, merge status, and validation runs).
- **`website/docs/features/<slug>/design.md`** owns intended feature behavior, boundaries, decisions, validation, and documentation impact.
- **Reader-facing pages under `website/docs/`** own current supported behavior.
- **`website/docs/features/<slug>/index.md`** owns the durable record of what a delivered feature provides and how its
  delivered behavior differs from its design; it does not record PRs, commits, or delivery status.
- **Beads** also owns planned work. The published docs describe delivered behavior only: the site build excludes a
  feature's directory until its `index.md` exists, and no page records planned, in-progress, or deferred work.
- **Code and tests** provide implementation evidence.

Use Beads instead of Markdown TODO lists for executable work. Use `bd remember` for durable cross-feature knowledge.

Track work in Beads when it spans sessions, has dependencies or acceptance criteria, belongs to a feature, or is
deferred for later. A small, self-contained fix completed in one change needs no issue; its commit message is the
record.

Features use an immutable lowercase filesystem-safe slug, shared by the feature docs directory and branch:

```text
website/docs/features/first-capability/
feat/first-capability
```

### Beads usage

Use dependency types intentionally:

- `blocks`: a real prerequisite that affects readiness;
- `parent-child`: hierarchy only;
- `related`: contextual association;
- `discovered-from`: provenance for work found during execution.

Use issue types intentionally. Feature roots are `epic`; ordinary bounded work is `task`; known defects are `bug`;
timeboxed fact-finding with explicit exit criteria is `spike`; durable architecture or product choices are `decision`;
and maintenance is `chore`. Use `feature` for standalone enhancements outside a feature epic. Introduce `story` only when
the repository actually manages a user-story backlog, and `milestone` only as a work-free aggregate.

For each tracked implementation task: claim it atomically, load only relevant design and documentation context, implement the smallest complete scope, update documentation in the same work unit, validate, run an isolated quality/security/maintainability review, record evidence, commit with the Beads ID, and close only after acceptance criteria pass. Untracked fixes follow the same steps except claiming, recording evidence, referencing a Beads ID, and closing. Use focused checks while iterating. Run the full repository suite once after review fixes stabilize and before commit; rerun it only after a failure or a later broad/shared fix.

## Documentation placement

Place documentation by reader intent:

- **Introduction**: purpose, audience, scope, boundaries, and conventions.
- **Architecture**: structure, ownership, interactions, invariants, and durable decisions.
- **Operator's Manual / Usage**: use, deployment, configuration, observability, maintenance, recovery, and troubleshooting where applicable.
- **Development Guide**: build, testing, extension, migration, and maintenance.
- **Reference**: exact commands, configuration, interfaces, schemas, fields, states, defaults, limits, terminology, and acceptance contracts.
- **Implemented Features**: one standalone record per completed feature of its delivered capability, behavior,
  and deviations from design, without transient delivery state.

Create project-specific pages only for durable reader needs. Feature designs name exact pages, not only documentation sections.

## Execution efficiency

Do bounded work directly in the controlling session. Launch subagents only when the user asks for delegation or a
distinct independent risk materially benefits from parallel read-only work. Do not launch a scout, planner, or reviewer
merely to save parent context, and never add unrequired confidence reviews.

Reuse existing review results and validation evidence while their inputs remain unchanged. After a fix, resume the
affected reviewer instead of starting a replacement. Do not rerun a successful check unless relevant inputs changed; use
one focused check while iterating and one full suite after review fixes stabilize.

Keep verbose output out of the conversation context. Redirect long command output to an ephemeral file, inspect only the
relevant failure excerpt, and report the command, result, and artifact path. Do not poll background work; continue useful
work or use event-driven waiting.

## Commit messages

Every changelog-visible `feat`, `fix`, `perf`, or `refactor` subject must use `<type>(<scope>): <summary>` or
`<type>(<scope>)!: <summary>`. Omitted internal types may be unscoped; release commits use `release: vX.Y.Z`. Choose the
owning subsystem, not a feature number or incidental file name. If `cog.toml` gains a scope allowlist, document the
scope taxonomy in README when present (otherwise the tooling reference) and update this guidance at the same time.

When a body records multiple discrete changes, decisions, or validation results, prefer a Markdown `-` list with one
idea per item. Use prose when sequence, causality, or rationale cannot be adequately expressed as a list; do not force a
body when the subject is sufficient.

For multiline messages, write the message to a temporary file and use `git commit -F <file>`; one argument containing literal newlines is also valid. A single `-m` is acceptable only for a subject-only commit. Never construct bodies with multiple `-m` flags or escaped `\n` text. Verify the resulting message before recording its SHA in Beads.

## Branches and delivery

Feature branches use `feat/<slug>`. When `wt` is available, treat JSON output from `wt switch --format json` as authoritative for branch and path.

Changes reach `dev` only through a pull request merged with GitHub's squash merge, the only method the `dev` ruleset
allows. GitHub signs the squash commit, keeping `dev` linear and signed; rebase merges are rejected because GitHub
cannot sign rebased commits. A pull request needs passing `validate`, `server-tests`, and `client-tests` checks and
resolved review threads. Never push directly to `dev` and never create a merge commit; local merges stay
fast-forward only.

`main` moves only through the Release workflow, which fast-forwards it to a validated `dev` commit and tags the
release. Never push to `main` or create `v*` tags directly; see `website/docs/development/releasing.md`.
