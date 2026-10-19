# Server agent guide

The Elixir/Phoenix control plane: Ash resources, AshJsonApi device and operator APIs, and a LiveView operator UI. Read
`website/docs/repository-structure.md` for the layout and `website/docs/modules/server-*.md` for module architecture.

## Commands

Run Mix through `mise x --` from `packages/server`; Elixir and Erlang come from this directory's `mise.toml`.

- `mise x -- mix setup`: fetch deps, set up the database and assets, and seed.
- `mise x -- mix test`: `db.ensure` starts a local Postgres container through `container`, `docker`, or `podman` when
  nothing listens on the configured port. Set `NIXSTASIS_DB_AUTOSTART=false` to disable that.
- `mise x -- mix precommit`: compile with warnings as errors, unlock unused deps, format, and test.
- `mise x -- mix ash.codegen --check`: confirm no pending migrations or snapshots. Follow the root `AGENTS.md` Ash
  Codegen rules when resources change.
- `mise x -- mix openapi.generate`: regenerate `priv/static/openapi.yaml` after changing JSON:API resources or routes,
  and commit it. `test/nixstasis_web/openapi_contract_test.exs` asserts against the committed file.

## Code layout

- Ash resources are registered in `Nixstasis.Domain` (`lib/nixstasis/domain.ex`). Context modules such as
  `lib/nixstasis/devices.ex` front the resources in the matching subdirectory.
- Custom Mix tasks live in `lib/mix/tasks/`.
- Use `Req` for HTTP requests.

## LiveView UI

- LiveViews get the app layout from `layout: {NixstasisWeb.Layouts, :app}` in `lib/nixstasis_web.ex`; templates do not
  wrap themselves in a layout component.
- Use `<.input>` and `<.icon>` from `core_components.ex`. Icons accept `hero-*` and `fa-*` names.
- Styling is Tailwind v4 with daisyUI component classes (`btn`, `table`, `modal`) and the Nixstasis theme in
  `assets/css/app.css`. Match the existing components.
- Put client-side behavior in LiveView hooks under `assets/js/hooks/`, imported from `assets/js/app.js`; never inline
  `<script>` tags in templates.
- LiveDebugger is off by default; enable it with `LIVE_DEBUGGER=true` on both `mix deps.get` and `mix phx.server`.

## Dependency usage rules

- Before working with a dependency such as Ash, AshJsonApi, AshPostgres, AshPhoenix, Igniter, or Phoenix, read its
  `deps/<package>/usage-rules.md` when it ships one. Run `mix deps.get` first if `deps/` is missing.
- Look up module and function docs with `h Module.function` in `iex -S mix`, task docs with `mix help <task>`, or the
  package's HexDocs.
