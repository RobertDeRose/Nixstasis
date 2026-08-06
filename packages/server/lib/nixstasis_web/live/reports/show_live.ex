defmodule NixstasisWeb.ReportLive.Show do
  use NixstasisWeb, :live_view

  alias Nixstasis.Reporting
  alias Nixstasis.SchemaOptions
  alias NixstasisWeb.Permissions

  @number_operators [
    {">", ">"},
    {">=", ">="},
    {"=", "="},
    {"<=", "<="},
    {"<", "<"}
  ]

  @string_operators [
    {"contains", "contains"},
    {"doesn't contain", "doesn't contain"},
    {"is", "is"},
    {"is not", "is not"}
  ]

  def mount(%{"id" => id}, session, socket) do
    if Permissions.can_view_reports?(session) do
      report = Reporting.get_custom_report!(id)

      if e2e_report?(report) do
        {:ok,
         socket
         |> put_flash(:error, "E2E internal reports are not available in this view.")
         |> push_navigate(to: ~p"/reports")}
      else
        fields = Reporting.report_fields(report)
        field_type_by_column = build_field_type_map(report, fields)
        preference_scope = Reporting.preference_scope(session)
        filter_column = first_field_key(fields)
        filter_operator = default_filter_operator(field_type_for_column(field_type_by_column, filter_column))

        {:ok,
         socket
         |> assign(:can_view_reports, true)
         |> assign(:can_manage_reports, Permissions.can_manage_reports?(session))
         |> assign(:report, report)
         |> assign(:fields, fields)
         |> assign(:field_type_by_column, field_type_by_column)
         |> assign(:results, [])
         |> assign(:preference_scope, preference_scope)
         |> assign(:preferences_enabled?, preference_scope != nil)
         |> assign(:preferences_reset?, false)
         |> assign(:sort_by, "")
         |> assign(:sort_dir, "asc")
         |> assign(:filter_column, filter_column)
         |> assign(:filter_operator, filter_operator)
         |> assign(:filter_value, "")
         |> assign(:operators, operators_for_type(field_type_for_column(field_type_by_column, filter_column)))}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to view reports.")
       |> push_navigate(to: ~p"/")}
    end
  end

  def handle_params(params, _url, socket) do
    if authorized_socket?(socket) do
      merged_view_state =
        params
        |> merge_with_saved_show_preferences(socket.assigns.report.id, socket.assigns.preference_scope)

      view_state =
        normalize_show_view_state(merged_view_state, socket.assigns.fields, socket.assigns.field_type_by_column)

      preferences_reset? = meaningful_show_view_state?(merged_view_state) and merged_view_state != view_state

      filters = to_filters(view_state)

      results =
        Reporting.run_custom_report(socket.assigns.report, %{
          "sort_by" => view_state["sort_by"],
          "sort_dir" => view_state["sort_dir"],
          "filters" => filters,
          "numeric_columns" => numeric_field_keys(socket.assigns.field_type_by_column),
          "limit" => 250
        })

      Reporting.save_view_preferences(
        socket.assigns.preference_scope,
        "reports:show:#{socket.assigns.report.id}",
        view_state
      )

      {:noreply,
       socket
       |> assign(:results, results)
       |> assign(:sort_by, view_state["sort_by"])
       |> assign(:sort_dir, view_state["sort_dir"])
       |> assign(:filter_column, view_state["filter_column"])
       |> assign(:filter_operator, view_state["filter_operator"])
       |> assign(:filter_value, view_state["filter_value"])
       |> assign(:preferences_reset?, preferences_reset?)
       |> assign(
         :operators,
         operators_for_type(field_type_for_column(socket.assigns.field_type_by_column, view_state["filter_column"]))
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_sort", %{"by" => by}, socket) do
    next_dir =
      if socket.assigns.sort_by == by and socket.assigns.sort_dir == "asc", do: "desc", else: "asc"

    {:noreply,
     push_patch(socket,
       to:
         show_path(socket, %{
           "sort_by" => by,
           "sort_dir" => next_dir
         })
     )}
  end

  def handle_event("apply_filters", %{"filter" => filter}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         show_path(socket, %{
           "filter_column" => filter["column"],
           "filter_operator" => filter["operator"],
           "filter_value" => filter["value"]
         })
     )}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         show_path(socket, %{
           "filter_value" => "",
           "filter_operator" =>
             default_filter_operator(
               field_type_for_column(socket.assigns.field_type_by_column, first_field_key(socket.assigns.fields))
             ),
           "filter_column" => first_field_key(socket.assigns.fields)
         })
     )}
  end

  defp merge_with_saved_show_preferences(params, report_id, preference_scope) do
    saved = Reporting.load_view_preferences(preference_scope, "reports:show:#{report_id}")

    %{
      "sort_by" => params["sort_by"] || saved["sort_by"],
      "sort_dir" => params["sort_dir"] || saved["sort_dir"],
      "filter_column" => params["filter_column"] || saved["filter_column"],
      "filter_operator" => params["filter_operator"] || saved["filter_operator"],
      "filter_value" => params["filter_value"] || saved["filter_value"]
    }
  end

  defp normalize_show_view_state(state, fields, field_type_by_column) do
    allowed_fields = Enum.map(fields, &(field_key(&1) || ""))
    fallback_field = first_field_key(fields)
    filter_column = normalize_sort_field(state["filter_column"], allowed_fields, fallback_field)

    %{
      "sort_by" => normalize_sort_field(state["sort_by"], allowed_fields),
      "sort_dir" => normalize_sort_dir(state["sort_dir"]),
      "filter_column" => filter_column,
      "filter_operator" =>
        normalize_filter_operator(
          state["filter_operator"],
          field_type_for_column(field_type_by_column, filter_column)
        ),
      "filter_value" => state["filter_value"] || ""
    }
  end

  defp meaningful_show_view_state?(state) do
    state["sort_by"] not in [nil, ""] or
      state["sort_dir"] not in [nil, ""] or
      state["filter_column"] not in [nil, ""] or
      state["filter_operator"] not in [nil, ""] or
      state["filter_value"] not in [nil, ""]
  end

  defp normalize_sort_field(field, allowed, fallback \\ "") do
    if field in allowed, do: field, else: fallback
  end

  defp normalize_sort_dir(dir) when dir in ["asc", "desc"], do: dir
  defp normalize_sort_dir(_), do: "asc"

  defp normalize_filter_operator(op, :number) when op in [">", ">=", "=", "<=", "<"], do: op

  defp normalize_filter_operator(op, :string)
       when op in ["contains", "doesn't contain", "is", "is not"],
       do: op

  defp normalize_filter_operator("in", :string), do: "contains"
  defp normalize_filter_operator("not in", :string), do: "doesn't contain"
  defp normalize_filter_operator(_op, type), do: default_filter_operator(type)

  defp to_filters(%{"filter_value" => value}) when value in [nil, ""], do: []

  defp to_filters(state) do
    [
      %{
        "column" => state["filter_column"],
        "operator" => state["filter_operator"],
        "value" => state["filter_value"]
      }
    ]
  end

  defp show_path(socket, overrides) do
    params = %{
      "sort_by" => overrides["sort_by"] || socket.assigns.sort_by,
      "sort_dir" => overrides["sort_dir"] || socket.assigns.sort_dir,
      "filter_column" => overrides["filter_column"] || socket.assigns.filter_column,
      "filter_operator" => overrides["filter_operator"] || socket.assigns.filter_operator,
      "filter_value" => overrides["filter_value"] || socket.assigns.filter_value
    }

    ~p"/reports/#{socket.assigns.report.id}?#{params}"
  end

  defp first_field_key([first | _]), do: field_key(first)
  defp first_field_key([]), do: ""

  defp field_key(field), do: field["alias"] || field["path"]

  defp build_field_type_map(report, fields) do
    type_by_path = schema_type_map(report)

    Map.new(fields, fn field ->
      key = field_key(field)
      path = field["path"] || field[:path]
      type = normalize_column_type(Map.get(type_by_path, path))
      {key, type}
    end)
  end

  defp schema_type_map(report) do
    schema_id = report.config["schema_id"] || report.config[:schema_id]
    schema_version = report.config["schema_version"] || report.config[:schema_version]

    refs =
      case SchemaOptions.list_bounded_schema_references() do
        {:ok, schema_refs} -> maybe_scope_refs(schema_refs, schema_id, schema_version)
        {:error, _} -> []
      end

    options =
      case refs do
        [] ->
          []

        [ref] ->
          case SchemaOptions.options_for(ref.schema_id, ref.schema_version, :report) do
            {:ok, %{options: options}} -> options
            _ -> []
          end

        _ ->
          case SchemaOptions.options_for_many(refs, :report) do
            {:ok, %{options: options, errors: []}} -> options
            _ -> []
          end
      end

    options
    |> Enum.reduce(%{}, fn option, acc ->
      key = option[:key]
      value_type = option[:value_type]

      if is_binary(key) and key != "" do
        Map.update(acc, key, value_type, &merge_schema_value_types(&1, value_type))
      else
        acc
      end
    end)
  end

  defp maybe_scope_refs(refs, schema_id, schema_version) do
    Enum.filter(refs, fn ref ->
      (not present_schema_value?(schema_id) or ref.schema_id == schema_id) and
        (not present_schema_value?(schema_version) or ref.schema_version == schema_version)
    end)
  end

  defp present_schema_value?(value), do: is_binary(value) and String.trim(value) != ""

  defp merge_schema_value_types(type, type), do: type
  defp merge_schema_value_types(_left, _right), do: "unknown"

  defp normalize_column_type(type) when type in ["integer", "number", "float", "decimal"], do: :number
  defp normalize_column_type(_), do: :string

  defp field_type_for_column(field_type_by_column, column) do
    Map.get(field_type_by_column || %{}, column, :string)
  end

  defp numeric_field_keys(field_type_by_column) do
    field_type_by_column
    |> Enum.filter(fn {_field, type} -> type == :number end)
    |> Enum.map(fn {field, _type} -> field end)
  end

  defp operators_for_type(:number), do: @number_operators
  defp operators_for_type(:string), do: @string_operators
  defp operators_for_type(_), do: @string_operators

  defp default_filter_operator(:number), do: "="
  defp default_filter_operator(:string), do: "is"
  defp default_filter_operator(_), do: "is"

  defp sort_indicator(sort_by, sort_dir, column) do
    if sort_by == column do
      if sort_dir == "asc", do: "↑", else: "↓"
    else
      ""
    end
  end

  defp e2e_report?(report) do
    source = report.config["source"] || report.config[:source]
    source == "e2e"
  end

  defp authorized_socket?(socket) do
    socket.assigns[:can_view_reports] == true
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div :if={!@preferences_enabled?} class="alert alert-soft alert-info mb-4" role="status">
        <span>Saved report view preferences are unavailable for this session.</span>
      </div>

      <div :if={@preferences_reset?} class="alert alert-soft alert-warning mb-4" role="status">
        <span>Saved report view preferences were invalid and have been reset to safe defaults.</span>
      </div>

      <div class="mb-8 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@report.name}</h1>
        </div>
        <div class="flex gap-3">
          <.link navigate={~p"/reports"} class={action_link_class(:view)}>
            Back to List
          </.link>
          <.link :if={@can_manage_reports} navigate={~p"/reports/#{@report.id}/edit"} class={action_link_class(:edit)}>
            Edit
          </.link>
        </div>
      </div>

      <form phx-change="apply_filters" class="mb-4 flex flex-wrap items-center gap-3">
        <select name="filter[column]" class="ui-select-sm-plain" value={@filter_column}>
          <option :for={field <- @fields} value={field_key(field)} selected={@filter_column == field_key(field)}>
            {field_key(field)}
          </option>
        </select>
        <select name="filter[operator]" class="ui-select-sm-plain" value={@filter_operator}>
          <option :for={{label, value} <- @operators} value={value} selected={@filter_operator == value}>
            {label}
          </option>
        </select>
        <input
          name="filter[value]"
          value={@filter_value}
          class="ui-input"
          placeholder="Filter value"
        />
        <button type="button" phx-click="clear_filters" class="btn btn-sm btn-ghost">Clear</button>
      </form>

      <div class="overflow-x-auto">
        <table class="table table-zebra">
          <thead>
            <tr>
              <%= for field <- @fields do %>
                <th>
                  <button
                    type="button"
                    phx-click="set_sort"
                    phx-value-by={field_key(field)}
                    class="link link-hover"
                  >
                    {field_key(field)} {sort_indicator(@sort_by, @sort_dir, field_key(field))}
                  </button>
                </th>
              <% end %>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @results do %>
              <tr>
                <%= for field <- @fields do %>
                  <td>
                    {Map.get(row, field_key(field))}
                  </td>
                <% end %>
              </tr>
            <% end %>
          </tbody>
        </table>
        <%= if Enum.empty?(@results) do %>
          <div class="p-6 text-center text-base-content/60">No data found matching report criteria.</div>
        <% end %>
      </div>
    </div>
    """
  end
end
