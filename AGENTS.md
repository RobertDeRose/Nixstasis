# AGENTS

Start here when working in this repository.

## Ground Rules

- Prefer the smallest correct change.
- Keep documentation and implementation aligned in the same unit of work.
- Do not treat a task as complete if the code and docs-driven feature docs disagree.

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
