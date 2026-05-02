defmodule NixstasisWeb.LiveDashboard.E2EPage do
  @moduledoc false

  use Phoenix.LiveDashboard.PageBuilder, refresher?: false

  import Ecto.Query
  import Phoenix.HTML.Form
  import Phoenix.LiveDashboard.PageBuilder

  alias Nixstasis.E2E
  alias Nixstasis.E2E.LogStore
  alias Nixstasis.E2E.Run
  alias Nixstasis.E2E.RunResult
  alias Nixstasis.Repo
  alias NixstasisWeb.LiveDashboard.E2ELogPresenter

  @menu_text "E2E Tests"
  @status_options ~w(all queued running passed failed blocked cancelled)
  @trigger_options ~w(all manual ci)
  @default_limit 50
  @runs_refresh_interval_ms 5_000
  @log_preview_bytes 50_000
  @run_sortable_fields ~w(id suite_id environment_label status trigger_source protocol_version started_at finished_at)a

  @impl true
  def menu_link(_, _), do: {:ok, @menu_text}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:filters, %{})
      |> assign(:journey_catalog, load_journey_catalog())
      |> assign(:visible_run_ids, [])
      |> assign(:visible_selected_count, 0)
      |> assign(:runs_table_refresh_tick, 0)
      |> assign(:selected_run_ids, MapSet.new())
      |> assign(:all_visible_runs_selected, false)
      |> assign(:show_delete_modal, false)
      |> assign(:delete_error, nil)
      |> assign(:selected_run, nil)
      |> assign(:selected_results, [])
      |> assign(:selected_result_journey_id, nil)
      |> assign(:selected_run_error, nil)
      |> assign(:expanded_journey_log, nil)
      |> assign(:expanded_journey_log_error, nil)
      |> assign(:expanded_journey_log_ref, nil)

    if connected?(socket) do
      schedule_runs_table_refresh()
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = parse_filters(params)
    visible_run_ids = fetch_visible_run_ids(filters, params)
    selected_run_ids = Map.get(socket.assigns, :selected_run_ids, MapSet.new())
    all_visible_runs_selected = all_visible_runs_selected?(selected_run_ids, visible_run_ids)
    visible_selected_count = visible_selected_count(selected_run_ids, visible_run_ids)
    run_id = params["run_id"]

    {selected_run, selected_run_error} =
      case run_id do
        nil ->
          {nil, nil}

        "" ->
          {nil, nil}

        id ->
          case E2E.get_run(id) do
            {:ok, run} -> {run, nil}
            {:error, :not_found} -> {nil, "Run #{id} not found"}
          end
      end

    selected_results = result_rows_for_selected_run(selected_run, socket.assigns.journey_catalog)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:visible_run_ids, visible_run_ids)
      |> assign(:visible_selected_count, visible_selected_count)
      |> assign(:all_visible_runs_selected, all_visible_runs_selected)
      |> assign(:selected_run, selected_run)
      |> assign(:selected_results, selected_results)
      |> assign(:selected_result_journey_id, nil)
      |> assign(:selected_run_error, selected_run_error)
      |> assign(:expanded_journey_log, nil)
      |> assign(:expanded_journey_log_error, nil)
      |> assign(:expanded_journey_log_ref, nil)
      |> assign(:delete_error, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    updates = %{
      status: Map.get(params, "status"),
      suite: Map.get(params, "suite"),
      environment: Map.get(params, "environment"),
      trigger: Map.get(params, "trigger")
    }

    to = merge_params(socket, updates)
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("select_run", %{"id" => run_id}, socket) do
    to = merge_params(socket, %{run_id: run_id})
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("select_result_journey", %{"journey_id" => journey_id}, socket) do
    if socket.assigns.selected_result_journey_id == journey_id do
      {:noreply,
       assign(socket,
         selected_result_journey_id: nil,
         expanded_journey_log: nil,
         expanded_journey_log_error: nil,
         expanded_journey_log_ref: nil
       )}
    else
      result = Enum.find(socket.assigns.selected_results, &(&1.journey_id == journey_id))

      {log, log_error, log_ref} = expanded_journey_log_state(result, journey_id)

      {:noreply,
       assign(socket,
         selected_result_journey_id: journey_id,
         expanded_journey_log: log,
         expanded_journey_log_error: log_error,
         expanded_journey_log_ref: log_ref
       )}
    end
  end

  def handle_event("toggle_run_selection", %{"id" => run_id}, socket) do
    selected =
      socket.assigns.selected_run_ids
      |> toggle_selection(run_id)

    {:noreply, assign_selection_state(socket, selected, socket.assigns.visible_run_ids)}
  end

  def handle_event("toggle_select_all_runs", _params, socket) do
    selected = socket.assigns.selected_run_ids
    visible = socket.assigns.visible_run_ids

    next_selected =
      if socket.assigns.all_visible_runs_selected do
        Enum.reduce(visible, selected, &MapSet.delete(&2, &1))
      else
        Enum.reduce(visible, selected, &MapSet.put(&2, &1))
      end

    {:noreply, assign_selection_state(socket, next_selected, visible)}
  end

  def handle_event("show_delete_selected_modal", _params, socket) do
    if MapSet.size(socket.assigns.selected_run_ids) == 0 do
      {:noreply, socket}
    else
      {:noreply, assign(socket, show_delete_modal: true, delete_error: nil)}
    end
  end

  def handle_event("cancel_delete_selected", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: false)}
  end

  def handle_event("confirm_delete_selected", _params, socket) do
    run_ids = MapSet.to_list(socket.assigns.selected_run_ids)
    deleted_set = MapSet.new(run_ids)

    case E2E.delete_runs(run_ids) do
      {:ok, _count} ->
        selected_run_id = socket.assigns.selected_run && socket.assigns.selected_run.id

        visible_run_ids =
          fetch_visible_run_ids(socket.assigns.filters, socket.assigns.page.params)

        socket =
          socket
          |> assign(:visible_run_ids, visible_run_ids)
          |> assign_selection_state(MapSet.new(), visible_run_ids)

        socket =
          assign(socket,
            show_delete_modal: false,
            delete_error: nil,
            expanded_journey_log: nil,
            expanded_journey_log_error: nil,
            expanded_journey_log_ref: nil
          )

        if selected_run_id && MapSet.member?(deleted_set, selected_run_id) do
          to = merge_params(socket, %{run_id: nil})
          {:noreply, push_patch(socket, to: to)}
        else
          {:noreply, socket}
        end

      {:error, reason} ->
        {:noreply,
         assign(socket,
           show_delete_modal: true,
           delete_error: "Failed to delete selected runs: #{inspect(reason)}"
         )}
    end
  end

  @impl true
  def handle_info(:refresh_runs_table, socket) do
    socket =
      if Map.has_key?(socket.assigns, :page) and Map.has_key?(socket.assigns, :filters) do
        visible_run_ids =
          fetch_visible_run_ids(socket.assigns.filters, socket.assigns.page.params)

        socket
        |> assign(:visible_run_ids, visible_run_ids)
        |> assign_selection_state(socket.assigns.selected_run_ids, visible_run_ids)
      else
        socket
      end
      |> assign(:runs_table_refresh_tick, socket.assigns.runs_table_refresh_tick + 1)

    schedule_runs_table_refresh()
    {:noreply, socket}
  end

  defp expanded_journey_log_state(%{log_ref: nil}, _journey_id), do: {nil, nil, nil}

  defp expanded_journey_log_state(%{log_ref: ref}, _journey_id) do
    case load_log(ref) do
      {:ok, entries, meta} -> {%{entries: entries, meta: meta}, nil, ref}
      {:error, message} -> {nil, message, ref}
    end
  end

  defp expanded_journey_log_state(_result, journey_id) do
    {nil, "Journey result was not found for #{journey_id}.", nil}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.row>
      <:col>
        <.card title="Filters" dom_id="e2e-filters-card">
          <form id="e2e-filters-form" phx-change="apply_filters">
            <div id="e2e-filters-grid">
              <div class="e2e-filter-group">
                <label for="e2e-filter-status">Status</label>
                <select id="e2e-filter-status" name="status" class="custom-select custom-select-sm">
                  {options_for_select(status_options(), Map.get(@filters, :status, "all"))}
                </select>
              </div>

              <div class="e2e-filter-group">
                <label for="e2e-filter-suite">Suite</label>
                <select id="e2e-filter-suite" name="suite" class="custom-select custom-select-sm">
                  {options_for_select(suite_options(), Map.get(@filters, :suite, "all"))}
                </select>
              </div>

              <div class="e2e-filter-group">
                <label for="e2e-filter-environment">Environment</label>
                <select id="e2e-filter-environment" name="environment" class="custom-select custom-select-sm">
                  {options_for_select(environment_options(), Map.get(@filters, :environment, "all"))}
                </select>
              </div>

              <div class="e2e-filter-group">
                <label for="e2e-filter-trigger">Trigger</label>
                <select id="e2e-filter-trigger" name="trigger" class="custom-select custom-select-sm">
                  {options_for_select(trigger_options(), Map.get(@filters, :trigger, "all"))}
                </select>
              </div>
            </div>
          </form>
          <div class="e2e-filters-footer">
            <div class="e2e-filters-help">
              Filter runs by status, suite, environment, and trigger source.
            </div>
            <div class="e2e-run-actions">
              <span class="text-muted">
                {MapSet.size(@selected_run_ids)} selected
              </span>
              <button
                type="button"
                class="btn btn-sm btn-secondary"
                phx-click="show_delete_selected_modal"
                disabled={MapSet.size(@selected_run_ids) == 0}
              >
                Delete Selected
              </button>
            </div>
          </div>
        </.card>
      </:col>
    </.row>

    <.live_table
      id="e2e-runs-table"
      dom_id="e2e-runs-table"
      page={@page}
      title="E2E Runs"
      rows_name="runs"
      search={true}
      default_sort_by={:started_at}
      row_fetcher={&fetch_runs(@filters, @selected_run_ids, @runs_table_refresh_tick, &1, &2)}
      row_attrs={&run_row_attrs(&1, @selected_run)}
    >
      <:col
        :let={run}
        field={:selected}
        header={
          select_all_header(
            @all_visible_runs_selected,
            @visible_selected_count,
            length(@visible_run_ids)
          )
        }
      >
        <input
          type="checkbox"
          class="checkbox checkbox-sm e2e-run-select-checkbox"
          checked={run.selected}
          phx-click="toggle_run_selection"
          phx-value-id={run.id}
          phx-stop-propagation
          aria-label={"Select run #{run.id}"}
        />
      </:col>
      <:col field={:id} header="Run ID" />
      <:col field={:suite_id} header="Suite" />
      <:col field={:environment_label} header="Environment" />
      <:col field={:status} header="Status" sortable={:desc} />
      <:col field={:trigger_source} header="Trigger" sortable={:desc} />
      <:col field={:protocol_version} header="Protocol" sortable={:desc} />
      <:col field={:started_at} header="Started" sortable={:desc} />
      <:col field={:finished_at} header="Finished" sortable={:desc} />
    </.live_table>

    <div class="tabular">
      <div class="d-flex justify-content-between align-items-start px-3 pt-3 pb-2">
        <h5 class="card-title mb-0">Journey Results</h5>
        <span class="text-muted small">{results_hint(@selected_run, @selected_run_error)}</span>
      </div>
      <div id="e2e-results-table" class="card tabular-card mb-4 mt-4">
        <div class="card-body p-0">
          <div class="dash-table-wrapper">
            <%= if @selected_results == [] do %>
              <div class="text-muted px-3 pb-3">No journey results for the selected run.</div>
            <% else %>
              <div class="table-responsive">
                <table class="table table-hover mt-0 dash-table">
                  <thead>
                    <tr>
                      <th>Journey</th>
                      <th>Description</th>
                      <th>Status</th>
                      <th>Failure Step</th>
                      <th>Duration (ms)</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for result <- @selected_results do %>
                      <% expanded? = @selected_result_journey_id == result.journey_id %>
                      <tr
                        class={["e2e-parent-row", expanded? && "active"]}
                        phx-click="select_result_journey"
                        phx-value-journey_id={result.journey_id}
                        phx-page-loading
                      >
                        <td>
                          <span class="e2e-expand-indicator" aria-hidden="true">
                            <%= if expanded? do %>
                              <svg viewBox="0 0 20 20" class="e2e-chevron-icon">
                                <path d="M5.5 7.5 10 12l4.5-4.5" />
                              </svg>
                            <% else %>
                              <svg viewBox="0 0 20 20" class="e2e-chevron-icon">
                                <path d="M7.5 5.5 12 10l-4.5 4.5" />
                              </svg>
                            <% end %>
                          </span>
                          <span>{result.journey_id}</span>
                        </td>
                        <td>{result.description}</td>
                        <td>{result.status}</td>
                        <td>{result.failure_step}</td>
                        <td>{result.duration_ms}</td>
                      </tr>
                      <%= if expanded? do %>
                        <tr class="e2e-child-row">
                          <td colspan="5">
                            <div class="e2e-inline-log">
                              <div class="e2e-inline-log-header">
                                <strong>Journey Log</strong>
                                <%= if @expanded_journey_log && @expanded_journey_log_ref == result.log_ref do %>
                                  <span class="text-muted e2e-inline-log-meta">
                                    {@expanded_journey_log.meta}
                                  </span>
                                <% end %>
                              </div>

                              <%= cond do %>
                                <% @expanded_journey_log && @expanded_journey_log_ref == result.log_ref -> %>
                                  <div
                                    id={"e2e-inline-log-scroll-anchor-#{result.journey_id}"}
                                    phx-hook="ScrollIntoViewOnMount"
                                  >
                                    <div
                                      id={"e2e-inline-log-entries-#{result.journey_id}"}
                                      class="e2e-inline-log-entries"
                                      phx-hook="SharedE2ELogViewer"
                                      data-log-payload={encoded_log_payload(@expanded_journey_log.entries)}
                                    />
                                  </div>
                                <% @expanded_journey_log_error && @expanded_journey_log_ref == result.log_ref -> %>
                                  <div class="text-danger">{@expanded_journey_log_error}</div>
                                <% is_nil(result.log_ref) -> %>
                                  <div class="text-muted">Log is unavailable for this journey.</div>
                                <% true -> %>
                                  <div class="text-muted">Log is unavailable for this journey.</div>
                              <% end %>
                            </div>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <%= if @show_delete_modal do %>
      <div class="e2e-modal-backdrop">
        <div class="e2e-modal-card">
          <h3>Delete Selected Runs?</h3>
          <p>
            This will permanently remove {MapSet.size(@selected_run_ids)} run(s) and their stored journey logs.
          </p>
          <%= if @delete_error do %>
            <p class="text-danger mb-2">{@delete_error}</p>
          <% end %>
          <div class="e2e-modal-actions">
            <button type="button" class="btn btn-sm btn-link" phx-click="cancel_delete_selected">
              Cancel
            </button>
            <button type="button" class="btn btn-sm btn-secondary" phx-click="confirm_delete_selected">
              Delete Runs
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp status_options do
    Enum.map(@status_options, fn value ->
      label = if value == "all", do: "All", else: String.capitalize(value)
      {label, value}
    end)
  end

  defp trigger_options do
    Enum.map(@trigger_options, fn value ->
      label = if value == "all", do: "All", else: String.upcase(value)
      {label, value}
    end)
  end

  defp suite_options do
    suites =
      Application.get_env(:nixstasis, :e2e, [])
      |> Keyword.get(:suites, %{})
      |> Map.keys()
      |> Enum.sort()

    [{"All", "all"} | Enum.map(suites, &{&1, &1})]
  end

  defp environment_options do
    envs =
      Application.get_env(:nixstasis, :e2e, [])
      |> Keyword.get(:environments, %{})
      |> Map.keys()
      |> Enum.sort()

    [{"All", "all"} | Enum.map(envs, &{&1, &1})]
  end

  defp load_journey_catalog do
    journey_dir = Path.expand("../client/scripts/e2e/journeys", File.cwd!())

    journey_dir
    |> Path.join("*.yaml")
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn path, acc ->
      case parse_journey_file(path) do
        {:ok, journey} -> Map.put(acc, journey.id, journey)
        :error -> acc
      end
    end)
  end

  defp parse_journey_file(path) do
    with {:ok, content} <- File.read(path),
         {:ok, journey_id} <- parse_journey_id(content) do
      description = parse_journey_description(content)
      steps = parse_journey_steps(content)

      {:ok, %{id: journey_id, description: description, steps: steps}}
    else
      _ -> :error
    end
  end

  defp parse_journey_id(content) do
    case parse_yaml_string(content, ~r/^id:\s*["']?([^"'\n]+)["']?\s*$/m) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  defp parse_journey_description(content) do
    parse_yaml_string(content, ~r/^description:\s*["']?([^"'\n]+)["']?\s*$/m) ||
      "No description available."
  end

  defp parse_yaml_string(content, regex) do
    case Regex.run(regex, content) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp parse_journey_steps(content) do
    {steps, current_step} =
      content
      |> String.split("\n")
      |> Enum.reduce({[], nil}, &parse_journey_step_line/2)

    steps
    |> append_step_if_present(current_step)
    |> Enum.reverse()
  end

  defp parse_journey_step_line(line, {steps, current_step}) do
    action = parse_step_action(line)
    expect = parse_step_expect(line)

    cond do
      is_binary(action) ->
        {append_step_if_present(steps, current_step), %{action: action, expect: ""}}

      is_binary(expect) and not is_nil(current_step) ->
        {steps, %{current_step | expect: expect}}

      true ->
        {steps, current_step}
    end
  end

  defp parse_step_action(line) do
    case Regex.run(~r/^\s*(?:-\s*)?action:\s*["']?([^"'\n]+)["']?\s*$/, line) do
      [_, action] -> String.trim(action)
      _ -> nil
    end
  end

  defp parse_step_expect(line) do
    case Regex.run(~r/^\s*expect:\s*["']?([^"'\n]+)["']?\s*$/, line) do
      [_, expect] -> String.trim(expect)
      _ -> nil
    end
  end

  defp append_step_if_present(steps, nil), do: steps

  defp append_step_if_present(steps, step) do
    if blank?(step.action) do
      steps
    else
      [step | steps]
    end
  end

  defp selected_journey_details(nil, _catalog),
    do: %{description: "No journey selected.", steps: []}

  defp selected_journey_details(journey_id, catalog) do
    Map.get(catalog, journey_id, %{
      id: journey_id,
      description: "No description available.",
      steps: []
    })
  end

  defp parse_filters(params) do
    %{
      status: normalize_filter(params["status"]),
      suite: normalize_filter(params["suite"]),
      environment: normalize_filter(params["environment"]),
      trigger: normalize_filter(params["trigger"])
    }
  end

  defp normalize_filter(nil), do: "all"
  defp normalize_filter(""), do: "all"
  defp normalize_filter("all"), do: "all"
  defp normalize_filter(value), do: value

  defp merge_params(socket, updates) do
    page = socket.assigns.page

    new_params =
      page.params
      |> Map.merge(stringify_keys(updates))
      |> Enum.reject(fn {_key, value} -> value in [nil, "", "all"] end)
      |> Map.new()

    live_dashboard_path(socket, page.route, page.node, page.params, new_params)
  end

  defp stringify_keys(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, Atom.to_string(key), value)
    end)
  end

  defp toggle_selection(selected, run_id) do
    if MapSet.member?(selected, run_id) do
      MapSet.delete(selected, run_id)
    else
      MapSet.put(selected, run_id)
    end
  end

  defp assign_selection_state(socket, selected_run_ids, visible_run_ids) do
    visible_selected_count = visible_selected_count(selected_run_ids, visible_run_ids)

    socket
    |> assign(:selected_run_ids, selected_run_ids)
    |> assign(:visible_selected_count, visible_selected_count)
    |> assign(
      :all_visible_runs_selected,
      all_visible_runs_selected?(selected_run_ids, visible_run_ids)
    )
  end

  defp all_visible_runs_selected?(_selected, []), do: false

  defp all_visible_runs_selected?(selected, visible_run_ids) do
    Enum.all?(visible_run_ids, &MapSet.member?(selected, &1))
  end

  defp visible_selected_count(selected, visible_run_ids) do
    Enum.count(visible_run_ids, &MapSet.member?(selected, &1))
  end

  defp fetch_visible_run_ids(filters, params) do
    table = run_table_params(params)

    query =
      Run
      |> apply_filters(filters)
      |> apply_search(table.search)
      |> apply_sort(table.sort_by, table.sort_dir)
      |> select([run], run.id)

    limited =
      case table.limit do
        false -> query
        nil -> limit(query, ^@default_limit)
        value -> limit(query, ^value)
      end

    Repo.all(limited)
  end

  defp run_table_params(params) do
    %{
      search: blank_to_nil(Map.get(params, "search")),
      sort_by: run_sort_by(Map.get(params, "sort_by")),
      sort_dir: run_sort_dir(Map.get(params, "sort_dir")),
      limit: run_limit(Map.get(params, "limit"))
    }
  end

  defp run_sort_by(sort_by) when is_binary(sort_by) do
    atom = String.to_existing_atom(sort_by)
    if atom in @run_sortable_fields, do: atom, else: :started_at
  rescue
    ArgumentError -> :started_at
  end

  defp run_sort_by(sort_by) when sort_by in @run_sortable_fields, do: sort_by
  defp run_sort_by(_), do: :started_at

  defp run_sort_dir("asc"), do: :asc
  defp run_sort_dir("desc"), do: :desc
  defp run_sort_dir(:asc), do: :asc
  defp run_sort_dir(:desc), do: :desc
  defp run_sort_dir(_), do: :desc

  defp run_limit(nil), do: @default_limit
  defp run_limit(false), do: false

  defp run_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} when value > 0 -> value
      _ -> @default_limit
    end
  end

  defp run_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp run_limit(_), do: @default_limit

  defp run_row_attrs(%{id: id}, selected_run) do
    attrs = [
      {"phx-click", "select_run"},
      {"phx-value-id", id},
      {"phx-page-loading", true},
      {"style", "cursor: pointer"}
    ]

    if selected_run && selected_run.id == id do
      [{"class", "table-active e2e-run-active"} | attrs]
    else
      attrs
    end
  end

  defp fetch_runs(filters, selected_run_ids, _runs_table_refresh_tick, params, _node) do
    %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

    query =
      Run
      |> apply_filters(filters)
      |> apply_search(search)

    total = Repo.aggregate(query, :count, :id)
    query = apply_sort(query, sort_by, sort_dir)

    limited =
      case limit do
        false -> query
        nil -> limit(query, ^@default_limit)
        value -> limit(query, ^value)
      end

    rows = Enum.map(Repo.all(limited), &run_row(&1, selected_run_ids))
    {rows, total}
  end

  defp apply_filters(query, filters) do
    query
    |> maybe_filter(:status, filters[:status])
    |> maybe_filter(:suite_id, filters[:suite])
    |> maybe_filter(:environment_label, filters[:environment])
    |> maybe_filter(:trigger_source, filters[:trigger])
  end

  defp maybe_filter(query, _field, "all"), do: query
  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    where(query, [r], field(r, ^field) == ^value)
  end

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query

  defp apply_search(query, search) do
    like = "%#{search}%"

    where(
      query,
      [r],
      ilike(r.id, ^like) or ilike(r.suite_id, ^like) or ilike(r.environment_label, ^like) or
        ilike(r.status, ^like) or ilike(r.trigger_source, ^like) or
        ilike(r.protocol_version, ^like)
    )
  end

  defp apply_sort(query, sort_by, dir) when sort_by in @run_sortable_fields do
    direction = if dir in [:asc, :desc], do: dir, else: :desc
    order_by(query, [r], [{^direction, field(r, ^sort_by)}])
  end

  defp apply_sort(query, _sort_by, _dir), do: order_by(query, [r], desc: r.started_at)

  defp run_row(%Run{} = run, selected_run_ids) do
    %{
      selected: MapSet.member?(selected_run_ids, run.id),
      id: run.id,
      suite_id: run.suite_id,
      environment_label: run.environment_label,
      status: run.status,
      trigger_source: run.trigger_source,
      protocol_version: run.protocol_version,
      started_at: run.started_at,
      finished_at: run.finished_at
    }
  end

  defp result_rows_for_selected_run(nil, _journey_catalog), do: []

  defp result_rows_for_selected_run(%Run{} = run, journey_catalog) do
    results =
      case run.results do
        loaded when is_list(loaded) ->
          loaded

        _ ->
          from(result in RunResult,
            where: result.run_id == ^run.id,
            order_by: [asc: result.journey_id]
          )
          |> Repo.all()
      end

    Enum.map(results, &result_row(&1, journey_catalog))
  end

  defp result_row(%RunResult{} = result, journey_catalog) do
    details = selected_journey_details(result.journey_id, journey_catalog)

    %{
      id: result.id,
      journey_id: result.journey_id,
      description: details.description,
      status: result.status,
      failure_step: result.failure_step,
      duration_ms: result.duration_ms,
      log_ref: result.log_ref
    }
  end

  defp results_hint(nil, nil), do: "Select a run row to load journey results."
  defp results_hint(nil, error), do: error
  defp results_hint(%Run{id: id}, _error), do: "Showing results for run #{id}"

  defp select_all_header(all_selected, visible_selected_count, visible_total_count) do
    checked_attr = if all_selected, do: ~s( checked="checked"), else: ""

    Phoenix.HTML.raw(
      ~s(<input type="checkbox" id="e2e-select-all-runs" class="checkbox checkbox-sm e2e-run-select-checkbox" phx-click="toggle_select_all_runs" phx-stop-propagation phx-hook="IndeterminateCheckbox" data-selected-count="#{visible_selected_count}" data-total-count="#{visible_total_count}" aria-label="Select all runs"#{checked_attr}>)
    )
  end

  defp schedule_runs_table_refresh do
    Process.send_after(self(), :refresh_runs_table, @runs_refresh_interval_ms)
  end

  defp load_log(nil), do: {:error, "No log reference available."}

  defp load_log(path) do
    with {:ok, expanded} <- LogStore.expand_log_path(path),
         {:ok, content} <- LogStore.read_log(expanded) do
      {:ok, E2ELogPresenter.parse_entries(maybe_truncate_log(content)), log_hint(expanded)}
    else
      {:error, :log_unavailable} ->
        {:error, "Log is unavailable (possibly pruned or deleted)."}

      {:error, :outside_allowed_dirs} ->
        {:error, "Log path is outside allowed directories."}

      {:error, {:read_failed, reason}} ->
        {:error, "Failed to read log: #{inspect(reason)}"}

      {:error, message} when is_binary(message) ->
        {:error, message}

      _ ->
        {:error, "Log file is not accessible."}
    end
  end

  defp maybe_truncate_log(content) when byte_size(content) <= @log_preview_bytes, do: content

  defp maybe_truncate_log(content) do
    binary_part(content, 0, @log_preview_bytes)
  end

  defp log_hint(path) do
    root = File.cwd!()
    "Path: #{relative_to(path, root)}"
  end

  defp relative_to(path, root) do
    path_parts = Path.split(Path.expand(path))
    root_parts = Path.split(Path.expand(root))
    {path_tail, root_tail} = drop_common_path_prefix(path_parts, root_parts)

    parts =
      List.duplicate("..", length(root_tail))
      |> Kernel.++(path_tail)

    case parts do
      [] -> "."
      _ -> Path.join(parts)
    end
  end

  defp drop_common_path_prefix([head | path_rest], [head | root_rest]) do
    drop_common_path_prefix(path_rest, root_rest)
  end

  defp drop_common_path_prefix(path_parts, root_parts), do: {path_parts, root_parts}

  defp encoded_log_payload(entries) when is_list(entries) do
    %{entries: entries}
    |> Jason.encode!()
    |> Base.encode64()
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
