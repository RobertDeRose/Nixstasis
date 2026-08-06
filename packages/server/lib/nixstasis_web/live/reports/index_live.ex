defmodule NixstasisWeb.ReportLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.Reporting
  alias Nixstasis.Reporting.CustomReport
  alias Nixstasis.SchemaOptions
  alias NixstasisWeb.Permissions

  @default_filters %{"name" => "", "field_query" => "", "field_queries" => []}

  def mount(_params, session, socket) do
    preference_scope = Reporting.preference_scope(session)

    if Permissions.can_view_reports?(session) do
      {:ok,
       socket
       |> assign(:can_view_reports, true)
       |> assign(:preference_scope, preference_scope)
       |> assign(:preferences_enabled?, preference_scope != nil)
       |> assign(:preferences_reset?, false)
       |> assign(:can_manage_reports, Permissions.can_manage_reports?(session))
       |> assign(:schema_field_options, schema_field_options())
       |> assign(:report_to_delete, nil)
       |> assign(:sort_by, "name")
       |> assign(:sort_dir, "asc")
       |> assign(:filters, @default_filters)
       |> assign(:reports, [])}
    else
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to view reports.")
       |> push_navigate(to: ~p"/")}
    end
  end

  def handle_params(params, _url, socket) do
    if authorized_socket?(socket) do
      if socket.assigns.live_action in [:new, :edit] and not socket.assigns.can_manage_reports do
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to manage reports.")
         |> push_navigate(to: ~p"/reports")}
      else
        merged_view_state =
          params
          |> merge_with_saved_index_preferences(socket.assigns.preference_scope)

        view_state = normalize_index_view_state(merged_view_state)
        preferences_reset? = meaningful_index_view_state?(merged_view_state) and merged_view_state != view_state

        reports = load_reports(view_state)

        Reporting.save_view_preferences(socket.assigns.preference_scope, "reports:index", view_state)

        socket =
          socket
          |> assign(:sort_by, view_state["sort_by"])
          |> assign(:sort_dir, view_state["sort_dir"])
          |> assign(:filters, view_state["filters"])
          |> assign(:preferences_reset?, preferences_reset?)
          |> assign(:reports, reports)
          |> apply_action(socket.assigns.live_action, params)

        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_sort", %{"by" => by}, socket) do
    next_dir =
      if socket.assigns.sort_by == by and socket.assigns.sort_dir == "asc", do: "desc", else: "asc"

    {:noreply, push_patch(socket, to: reports_path(socket, %{"sort_by" => by, "sort_dir" => next_dir}))}
  end

  def handle_event("filter_reports", %{"filters" => filters}, socket) do
    normalized_filters = normalize_filters(filters)
    {:noreply, push_patch(socket, to: reports_path(socket, %{"filters" => normalized_filters}))}
  end

  def handle_event("add_field_filter_select", %{"field" => selected_field}, socket) do
    case normalize_selected_field(selected_field, socket.assigns.schema_field_options) do
      nil -> {:noreply, socket}
      key -> add_field_filter_key(socket, key)
    end
  end

  def handle_event("remove_field_filter", %{"field" => selected_field}, socket) do
    field_queries =
      socket.assigns.filters["field_queries"]
      |> normalize_field_queries()
      |> Enum.reject(&(&1 == selected_field))

    {:noreply, push_patch(socket, to: reports_path(socket, %{"filters" => %{"field_queries" => field_queries}}))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         reports_path(socket, %{
           "filters" => @default_filters,
           "sort_by" => socket.assigns.sort_by,
           "sort_dir" => socket.assigns.sort_dir
         })
     )}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    if socket.assigns.can_manage_reports do
      report = Reporting.get_custom_report!(id)
      {:noreply, assign(socket, :report_to_delete, report)}
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to delete reports.")}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :report_to_delete, nil)}
  end

  def handle_event("delete_report", _params, %{assigns: %{report_to_delete: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("delete_report", _params, socket) do
    if socket.assigns.can_manage_reports do
      case Reporting.delete_custom_report(socket.assigns.report_to_delete) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Report deleted")
           |> assign(:report_to_delete, nil)
           |> push_patch(to: reports_path(socket))}

        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Report deleted")
           |> assign(:report_to_delete, nil)
           |> push_patch(to: reports_path(socket))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete report.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to delete reports.")}
    end
  end

  def handle_info({NixstasisWeb.ReportLive.FormComponent, {:saved, report}}, socket) do
    if e2e_report?(report) do
      {:noreply, push_patch(socket, to: reports_path(socket))}
    else
      {:noreply,
       socket
       |> put_flash(:info, "Report saved")
       |> push_patch(to: reports_path(socket))}
    end
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Report")
    |> assign(:report, %CustomReport{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Report")
    |> assign(:report, Reporting.get_custom_report!(id))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Custom Reports")
    |> assign(:report, nil)
  end

  defp normalize_index_view_state(params) do
    filters =
      @default_filters
      |> Map.merge(params["filters"] || %{})
      |> Map.take(["name", "field_query", "field_queries"])
      |> normalize_filters()

    %{
      "sort_by" => normalize_sort_by(params["sort_by"]),
      "sort_dir" => normalize_sort_dir(params["sort_dir"]),
      "filters" => filters
    }
  end

  defp meaningful_index_view_state?(state) do
    state["sort_by"] not in [nil, ""] or
      state["sort_dir"] not in [nil, ""] or
      state["filters"] not in [nil, %{}, @default_filters]
  end

  defp merge_with_saved_index_preferences(params, preference_scope) do
    saved = Reporting.load_view_preferences(preference_scope, "reports:index")
    has_filters_param? = Map.has_key?(params, "filters")

    filters =
      if has_filters_param? do
        params["filters"]
      else
        saved["filters"]
      end

    %{
      "sort_by" => params["sort_by"] || saved["sort_by"],
      "sort_dir" => params["sort_dir"] || saved["sort_dir"],
      "filters" => merge_default_filters(filters)
    }
  end

  defp merge_default_filters(filters) when is_map(filters), do: Map.merge(@default_filters, filters)
  defp merge_default_filters(_), do: @default_filters

  defp normalize_sort_by(by) when by in ["name"], do: by
  defp normalize_sort_by(_), do: "name"

  defp normalize_sort_dir(dir) when dir in ["asc", "desc"], do: dir
  defp normalize_sort_dir(_), do: "asc"

  defp load_reports(view_state) do
    Reporting.list_custom_reports_with_view(%{
      "sort_by" => view_state["sort_by"],
      "sort_dir" => view_state["sort_dir"],
      "filters" => [],
      "name_query" => view_state["filters"]["name"],
      "field_query" => view_state["filters"]["field_query"],
      "field_queries" => view_state["filters"]["field_queries"]
    })
  end

  defp reports_path(socket, overrides \\ %{}) do
    filters = Map.merge(socket.assigns.filters, overrides["filters"] || %{})
    sort_by = overrides["sort_by"] || socket.assigns.sort_by
    sort_dir = overrides["sort_dir"] || socket.assigns.sort_dir

    params = %{
      "sort_by" => sort_by,
      "sort_dir" => sort_dir,
      "filters" => filters
    }

    case socket.assigns.live_action do
      :edit -> ~p"/reports?#{params}"
      :new -> ~p"/reports?#{params}"
      :index -> ~p"/reports?#{params}"
    end
  end

  defp e2e_report?(report) do
    source = report.config["source"] || report.config[:source]
    source == "e2e"
  end

  defp sort_indicator(sort_by, sort_dir, column) do
    if sort_by == column do
      if sort_dir == "asc", do: "↑", else: "↓"
    else
      ""
    end
  end

  defp authorized_socket?(socket) do
    socket.assigns[:can_view_reports] == true
  end

  defp normalize_filters(filters) when not is_map(filters), do: @default_filters

  defp normalize_filters(filters) do
    %{
      "name" => normalize_text_filter(filters["name"]),
      "field_query" => normalize_text_filter(filters["field_query"]),
      "field_queries" => normalize_field_queries(filters["field_queries"] || filters["field_query"])
    }
  end

  defp normalize_text_filter(value) when is_binary(value), do: String.trim(value)
  defp normalize_text_filter(_), do: ""

  defp normalize_field_queries(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> normalize_field_queries()
  end

  defp normalize_field_queries(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase(String.trim(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_field_queries(_), do: []

  defp schema_field_options do
    options =
      case SchemaOptions.options_for_many(SchemaOptions.list_schema_references(), :report) do
        {:ok, %{options: options}} -> options
        _ -> []
      end

    options
    |> Enum.reduce(%{}, fn option, acc ->
      key = option[:key]
      label = option[:label] || key

      if is_binary(key) and key != "" do
        Map.put_new(acc, String.downcase(key), %{key: String.downcase(key), label: label})
      else
        acc
      end
    end)
    |> Map.values()
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  defp normalize_selected_field(selected_field, field_options) when is_binary(selected_field) do
    candidate = String.downcase(String.trim(selected_field))

    cond do
      candidate == "" ->
        nil

      Enum.any?(field_options, &(&1.key == candidate)) ->
        candidate

      true ->
        field_options
        |> Enum.find(fn option -> String.downcase(option.label || "") == candidate end)
        |> case do
          %{key: key} -> key
          _ -> nil
        end
    end
  end

  defp normalize_selected_field(_, _), do: nil

  defp add_field_filter_key(socket, new_key) do
    field_queries =
      (socket.assigns.filters["field_queries"] || [])
      |> normalize_field_queries()
      |> then(fn existing ->
        if new_key in existing, do: existing, else: existing ++ [new_key]
      end)

    {:noreply, push_patch(socket, to: reports_path(socket, %{"filters" => %{"field_queries" => field_queries}}))}
  end

  defp field_label_for_key(key, field_options) do
    field_options
    |> Enum.find(%{label: key}, &(&1.key == key))
    |> Map.get(:label)
  end

  defp available_field_options(field_options, selected_field_keys) do
    selected = MapSet.new(normalize_field_queries(selected_field_keys))

    Enum.reject(field_options, fn option ->
      option.key in selected
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="ui-page-shell">
      <.header>
        Custom Reports
        <:actions>
          <.link :if={@can_manage_reports} patch={~p"/reports/new"}>
            <.button>Create Report</.button>
          </.link>
        </:actions>
      </.header>

      <div :if={!@preferences_enabled?} class="alert alert-soft alert-info mb-4" role="status">
        <span>Saved report view preferences are unavailable for this session.</span>
      </div>

      <div :if={@preferences_reset?} class="alert alert-soft alert-warning mb-4" role="status">
        <span>Saved report view preferences were invalid and have been reset to safe defaults.</span>
      </div>

      <div class="mb-4 grid grid-cols-1 gap-3 lg:grid-cols-[minmax(260px,420px)_minmax(320px,1fr)_auto] lg:items-start">
        <form phx-change="filter_reports" class="w-full">
          <label class="ui-label-strong">Filter by report name</label>
          <input
            type="text"
            name="filters[name]"
            value={@filters["name"]}
            placeholder="Fuzzy match, case-insensitive"
            class="ui-input-sm"
          />
          <input type="hidden" name="filters[field_query]" value={@filters["field_query"]} />
          <%= for field <- @filters["field_queries"] do %>
            <input type="hidden" name="filters[field_queries][]" value={field} />
          <% end %>
        </form>

        <div class="w-full">
          <label class="ui-label-strong">
            Filter by included schema fields
          </label>
          <form phx-change="add_field_filter_select" class="w-full">
            <select name="field" class="ui-select-sm">
              <option value="">Select a schema field…</option>
              <option
                :for={option <- available_field_options(@schema_field_options, @filters["field_queries"])}
                value={option.key}
              >
                {option.label}
              </option>
            </select>
          </form>
          <div class="mt-2 flex flex-wrap gap-2">
            <span
              :for={field <- @filters["field_queries"]}
              class="badge badge-neutral gap-1 px-2 py-2 text-xs"
            >
              {field_label_for_key(field, @schema_field_options)}
              <button
                type="button"
                phx-click="remove_field_filter"
                phx-value-field={field}
                class="rounded-full p-0.5 text-base-content/80 hover:text-base-content"
                aria-label={"Remove field filter #{field}"}
              >
                <.icon name="hero-x-mark" class="size-3.5" />
              </button>
            </span>
          </div>
        </div>

        <button type="button" phx-click="clear_filters" class="btn btn-sm btn-ghost lg:mt-6">
          Clear
        </button>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-zebra table-fixed">
          <thead>
            <tr>
              <th class="w-1/2 min-w-[20rem]">
                <button type="button" phx-click="set_sort" phx-value-by="name" class="link link-hover">
                  Name {sort_indicator(@sort_by, @sort_dir, "name")}
                </button>
              </th>
              <th class="w-1/2">Schema Fields</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @reports}>
              <td class="w-1/2 min-w-[20rem]">
                <div class="flex items-center gap-2">
                  <button
                    :if={@can_manage_reports}
                    type="button"
                    phx-click="confirm_delete"
                    phx-value-id={row["id"]}
                    class="btn btn-ghost btn-xs px-1 text-error hover:bg-error/10"
                    aria-label={"Delete report #{row["name"]}"}
                    title="Delete report"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                  <.link
                    :if={@can_manage_reports}
                    patch={~p"/reports/#{row["id"]}/edit"}
                    class="btn btn-ghost btn-xs px-1 text-info hover:bg-info/10"
                    aria-label={"Edit report #{row["name"]}"}
                    title="Edit report"
                  >
                    <.icon name="hero-pencil-square" class="size-4" />
                  </.link>
                  <.link navigate={~p"/reports/#{row["id"]}"} class="link link-primary font-bold">
                    {row["name"]}
                  </.link>
                </div>
              </td>
              <td class="w-1/2">
                <div class="flex max-w-full flex-wrap gap-1.5">
                  <span :for={field <- row["field_labels"]} class="badge badge-ghost badge-sm">
                    {field}
                  </span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%= if Enum.empty?(@reports) do %>
        <div class="p-6 text-center text-base-content/60">
          No reports found. Create one to get started.
        </div>
      <% end %>

      <.modal :if={@live_action in [:new, :edit]} id="report-modal" show on_cancel={JS.patch(~p"/reports")}>
        <.live_component
          module={NixstasisWeb.ReportLive.FormComponent}
          id={@report.id || :new}
          title={@page_title}
          action={@live_action}
          report={@report}
          patch={~p"/reports"}
        />
      </.modal>

      <.modal :if={@report_to_delete} id="delete-report-modal" show on_cancel={JS.push("cancel_delete")}>
        <div class="space-y-4">
          <h3 class="text-lg font-semibold">Delete Report</h3>
          <p>
            Are you sure you want to delete <span class="font-bold">{@report_to_delete.name}</span>?
            This action cannot be undone.
          </p>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_delete">Cancel</button>
            <button type="button" class="btn btn-error btn-sm" phx-click="delete_report">Delete</button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end
end
