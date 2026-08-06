defmodule NixstasisWeb.ReportLive.FormComponent do
  use NixstasisWeb, :live_component

  alias Nixstasis.Reporting
  alias Nixstasis.SchemaOptions

  @all_scope "__all__"

  @impl true
  def update(%{report: report} = assigns, socket) do
    schema_refs = SchemaOptions.list_schema_references()

    selected_schema_id =
      normalize_scope_value(config_value(report.config, "schema_id"), @all_scope)

    selected_schema_version =
      normalize_scope_value(config_value(report.config, "schema_version"), nil)

    {schema_options, schema_error} =
      fetch_schema_options(schema_refs, selected_schema_id, selected_schema_version)

    {fields, filters} = hydrate_builder_rows(report)
    report_name = normalize_report_name(report.name || "")

    socket =
      socket
      |> assign(assigns)
      |> assign(:all_scope, @all_scope)
      |> assign(:report_name, report_name)
      |> assign(:fields, fields)
      |> assign(:filters, filters)
      |> assign(:schema_refs, schema_refs)
      |> assign(:selected_schema_id, selected_schema_id)
      |> assign(:selected_schema_version, selected_schema_version)
      |> assign_schema_option_assigns(schema_options)
      |> assign(:schema_error, schema_error)
      |> assign(:schema_issue, schema_issue_for_error(schema_error))
      |> assign(:report_name_error, nil)
      |> assign(:recent_enter_added_field_id, nil)
      |> maybe_focus_first_column_field(assigns, fields)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    name = normalize_report_name(Map.get(params, "name", socket.assigns.report_name))

    {:noreply,
     socket
     |> assign(:report_name, name)
     |> maybe_validate_report_name(params, name)}
  end

  def handle_event("set_schema_id", %{"schema_id" => schema_id}, socket) do
    selected_schema_id = normalize_scope_value(schema_id, @all_scope)
    selected_schema_version = first_schema_version(socket.assigns.schema_refs, selected_schema_id)

    {schema_options, schema_error} =
      fetch_schema_options(
        socket.assigns.schema_refs,
        selected_schema_id,
        selected_schema_version
      )

    {:noreply,
     socket
     |> assign(:selected_schema_id, selected_schema_id)
     |> assign(:selected_schema_version, selected_schema_version)
     |> assign(:recent_enter_added_field_id, nil)
     |> clear_invalid_selections(schema_options, schema_error)}
  end

  def handle_event("set_schema_version", %{"schema_version" => schema_version}, socket) do
    selected_schema_version =
      normalize_explicit_schema_version(
        schema_version,
        first_schema_version(socket.assigns.schema_refs, socket.assigns.selected_schema_id)
      )

    {schema_options, schema_error} =
      fetch_schema_options(
        socket.assigns.schema_refs,
        socket.assigns.selected_schema_id,
        selected_schema_version
      )

    {:noreply,
     socket
     |> assign(:selected_schema_version, selected_schema_version)
     |> assign(:recent_enter_added_field_id, nil)
     |> clear_invalid_selections(schema_options, schema_error)}
  end

  def handle_event("add_field", _, socket) do
    new_field = %{id: Ecto.UUID.generate(), path: "", alias: ""}
    fields = socket.assigns.fields ++ [new_field]

    {:noreply,
     socket
     |> assign(:fields, fields)
     |> assign(:recent_enter_added_field_id, nil)
     |> push_event("focus_schema_field", %{id: column_path_select_id(new_field.id)})}
  end

  def handle_event("remove_field", %{"id" => id}, socket) do
    fields =
      socket.assigns.fields
      |> Enum.reject(&(&1.id == id))
      |> ensure_minimum_one_field(socket.assigns.fields)

    {:noreply,
     socket
     |> assign(:fields, fields)
     |> clear_recent_enter_added_field(id)}
  end

  def handle_event("update_field", %{"id" => _, "key" => _} = params, socket) do
    update_report_field(socket, params)
  end

  def handle_event("update_field", params, socket) do
    case parse_field_event_params(params) do
      {:ok, id, key, value} ->
        update_report_field(socket, %{"id" => id, "key" => Atom.to_string(key), "value" => value})

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("add_filter", _, socket) do
    new_filter = %{id: Ecto.UUID.generate(), field: "", operator: "=", value: ""}
    filters = socket.assigns.filters ++ [new_filter]

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> push_event("focus_filter_field", %{id: filter_field_select_id(new_filter.id)})}
  end

  def handle_event("remove_filter", %{"id" => id}, socket) do
    remove_filter_and_focus(socket, id)
  end

  def handle_event("add_filter_field_as_column", %{"filter_id" => filter_id}, socket) do
    add_filter_field_as_column(socket, filter_id)
  end

  def handle_event("update_filter", %{"id" => _, "key" => _} = params, socket) do
    update_report_filter(socket, params)
  end

  def handle_event("update_filter", params, socket) do
    case parse_filter_event_params(params) do
      {:ok, id, key, value} ->
        update_report_filter(socket, %{"id" => id, "key" => Atom.to_string(key), "value" => value})

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("column_title_keydown", %{"id" => id, "key" => key}, socket) do
    handle_column_title_keydown(socket, id, key)
  end

  def handle_event("column_title_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("schema_field_keydown", %{"field_id" => id, "key" => key}, socket) do
    maybe_remove_field_row(socket, id, key)
  end

  def handle_event("schema_field_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("filter_field_keydown", %{"filter_id" => id, "key" => key}, socket) do
    maybe_remove_filter_row(socket, id, key)
  end

  def handle_event("filter_field_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("filter_value_keydown", %{"id" => id, "key" => key}, socket) do
    handle_filter_value_keydown(socket, id, key)
  end

  def handle_event("filter_value_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", params, socket) do
    save_ctx = build_save_context(socket, params)
    maybe_record_invalid_attempt(save_ctx.validation)

    cond do
      save_ctx.name_taken? ->
        {:noreply,
         socket
         |> assign_save_state(save_ctx)
         |> assign(:report_name_error, "Report title is already used.")
         |> put_flash(:error, "Choose a unique report title.")}

      filters_have_invalid_value_types?(
        save_ctx.submitted_filters,
        schema_option_types(socket.assigns.schema_options)
      ) ->
        {:noreply,
         socket
         |> assign_save_state(save_ctx)
         |> put_flash(:error, "Please correct filter value types before saving.")}

      not is_nil(save_ctx.schema_error) ->
        message = SchemaOptions.schema_issue_message(save_ctx.schema_error)

        {:noreply,
         socket
         |> assign_save_state(save_ctx)
         |> assign(:schema_issue, message)
         |> put_flash(:error, message)}

      save_ctx.validation.valid ->
        maybe_record_first_attempt(save_ctx.submitted_fields, save_ctx.submitted_filters)
        persist_save(socket, save_ctx)

      true ->
        {:noreply,
         socket
         |> assign_save_state(save_ctx)
         |> assign(:schema_issue, "Some selected fields are invalid for the active schema scope.")
         |> put_flash(:error, "Please reselect invalid fields before saving.")}
    end
  end

  defp persist_report(%{id: nil}, report_params),
    do: Reporting.create_custom_report(report_params)

  defp persist_report(report, report_params),
    do: Reporting.update_custom_report(report, report_params)

  defp success_message(%{id: nil}), do: "Report created successfully"
  defp success_message(_), do: "Report updated successfully"

  defp build_save_context(socket, params) do
    submitted_name =
      params["name"] ||
        socket.assigns.report_name ||
        socket.assigns.report.name ||
        ""

    normalized_name = normalize_report_name(submitted_name)

    submitted_schema_id =
      normalize_scope_value(Map.get(params, "schema_id"), socket.assigns.selected_schema_id)

    submitted_schema_version =
      case Map.fetch(params, "schema_version") do
        {:ok, value} ->
          normalize_explicit_schema_version(value, nil)

        :error ->
          normalize_scope_value(
            socket.assigns.selected_schema_version,
            first_schema_version(socket.assigns.schema_refs, submitted_schema_id)
          )
      end

    submitted_fields =
      submitted_fields_from_params(
        params,
        socket.assigns.fields,
        schema_option_labels(socket.assigns.schema_options)
      )

    submitted_filters = submitted_filters_from_params(params, socket.assigns.filters)

    {validation, schema_error} =
      validate_current_schema(
        submitted_schema_id,
        submitted_schema_version,
        submitted_fields,
        submitted_filters
      )

    report_params = %{
      "name" => normalized_name,
      "config" => %{
        source: "telemetry",
        schema_id: persisted_schema_id(submitted_schema_id),
        schema_version: persisted_schema_version(submitted_schema_id, submitted_schema_version),
        fields: Enum.map(submitted_fields, &Map.take(&1, [:path, :alias])),
        filters: Enum.map(submitted_filters, &Map.take(&1, [:field, :operator, :value]))
      }
    }

    %{
      normalized_name: normalized_name,
      submitted_schema_id: submitted_schema_id,
      submitted_schema_version: submitted_schema_version,
      submitted_fields: submitted_fields,
      submitted_filters: submitted_filters,
      validation: validation,
      schema_error: schema_error,
      report_params: report_params,
      name_taken?: name_taken_for_other_report?(socket.assigns.report, normalized_name)
    }
  end

  defp validate_current_schema(@all_scope, schema_version, fields, filters) do
    {schema_options, schema_error} =
      SchemaOptions.list_schema_references()
      |> fetch_schema_options(@all_scope, schema_version)

    {validate_selected_keys(fields, filters, schema_options), schema_error}
  end

  defp validate_current_schema(schema_id, schema_version, fields, filters)
       when is_binary(schema_id) and schema_id != "" and schema_version in [nil, ""] do
    {schema_options, schema_error} =
      SchemaOptions.list_schema_references()
      |> fetch_schema_options(schema_id, nil)

    {validate_selected_keys(fields, filters, schema_options), schema_error}
  end

  defp validate_current_schema(schema_id, schema_version, fields, filters)
       when is_binary(schema_id) and schema_id != "" do
    validation =
      SchemaOptions.validate_selections(
        :report,
        schema_id,
        schema_version,
        schema_selections(fields, filters)
      )

    {validation, schema_error_from_validation(validation)}
  end

  defp validate_current_schema(_schema_id, _schema_version, fields, filters) do
    {validate_selected_keys(fields, filters, []), :invalid}
  end

  defp schema_selections(fields, filters) do
    Enum.map(fields, &%{"slot_id" => &1.id, "selected_key" => &1.path}) ++
      Enum.map(filters, &%{"slot_id" => &1.id, "selected_key" => &1.field})
  end

  defp schema_error_from_validation(%{issues: issues}) do
    cond do
      Enum.any?(issues, &(schema_issue_code(&1) == "schema_conflict")) -> :conflict
      Enum.any?(issues, &(schema_issue_code(&1) == "schema_unavailable")) -> :not_found
      Enum.any?(issues, &(schema_issue_code(&1) == "schema_access_lost")) -> :invalid
      true -> nil
    end
  end

  defp schema_error_from_validation(_), do: :invalid

  defp schema_issue_code(issue), do: Map.get(issue, :issue_code) || Map.get(issue, "issue_code")

  defp assign_save_state(socket, save_ctx) do
    socket
    |> assign(:report_name, save_ctx.normalized_name)
    |> assign(:selected_schema_id, save_ctx.submitted_schema_id)
    |> assign(:selected_schema_version, save_ctx.submitted_schema_version)
    |> assign(:schema_error, save_ctx.schema_error)
    |> assign(:fields, save_ctx.submitted_fields)
    |> assign(:filters, save_ctx.submitted_filters)
  end

  defp persist_save(socket, save_ctx) do
    case persist_report(socket.assigns.report, save_ctx.report_params) do
      {:ok, report} ->
        notify_parent({:saved, report})

        {:noreply,
         socket
         |> put_flash(:info, success_message(socket.assigns.report))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ash.Error.Invalid{} = error} ->
        handle_persist_invalid(socket, error)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to save report")}
    end
  end

  defp handle_persist_invalid(socket, error) do
    if duplicate_report_name_error?(error) do
      {:noreply,
       socket
       |> assign(:report_name_error, "Report title is already used.")
       |> put_flash(:error, "Choose a unique report title.")}
    else
      {:noreply, put_flash(socket, :error, "Unable to save report")}
    end
  end

  defp name_taken_for_other_report?(%{id: nil}, normalized_name),
    do: Reporting.custom_report_name_taken?(normalized_name)

  defp name_taken_for_other_report?(report, normalized_name) do
    existing_name = normalize_report_name(report.name || "")

    if String.downcase(existing_name) == String.downcase(normalized_name) do
      false
    else
      Reporting.custom_report_name_taken?(normalized_name)
    end
  end

  defp hydrate_builder_rows(report) do
    config = report.config || %{}
    config_fields = config_value(config, "fields") || []
    config_filters = config_value(config, "filters") || []

    fields =
      config_fields
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn field ->
        %{
          id: Ecto.UUID.generate(),
          path: config_value(field, "path") || "",
          alias: config_value(field, "alias") || ""
        }
      end)
      |> ensure_minimum_one_field([%{id: Ecto.UUID.generate(), path: "", alias: ""}])

    filters =
      config_filters
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn filter ->
        %{
          id: Ecto.UUID.generate(),
          field: config_value(filter, "field") || "",
          operator: normalize_filter_operator(config_value(filter, "operator") || "="),
          value: config_value(filter, "value") || ""
        }
      end)

    {fields, filters}
  end

  defp config_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, config_atom_key(key))
  end

  defp config_value(_, _), do: nil

  defp config_atom_key("schema_id"), do: :schema_id
  defp config_atom_key("fields"), do: :fields
  defp config_atom_key("filters"), do: :filters
  defp config_atom_key("path"), do: :path
  defp config_atom_key("alias"), do: :alias
  defp config_atom_key("field"), do: :field
  defp config_atom_key("operator"), do: :operator
  defp config_atom_key("value"), do: :value
  defp config_atom_key(_), do: nil

  defp normalize_filter_operator(op) when op in ["=", "!=", ">", "<", ">=", "<=", "=="], do: op
  defp normalize_filter_operator(_), do: "="

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Define columns and filters for your report.</:subtitle>
      </.header>

      <div class="py-4">
        <form
          id="report-builder-form"
          phx-hook="ReportBuilderKeyboard"
          phx-submit="save"
          phx-change="validate"
          phx-target={@myself}
        >
          <div class="mb-6">
            <label class="block text-sm font-medium text-base-content mb-2">Report Name</label>
            <input type="hidden" name="report_id" value={@report.id || ""} />
            <input
              id="report-name-input"
              phx-hook={if @action == :edit, do: nil, else: "ReportNameAutofocus"}
              type="text"
              name="name"
              value={@report_name}
              class="input w-full"
              placeholder="e.g. Daily Temperature Check"
              disabled={@action == :edit}
              required
            />
            <%= if @report_name_error do %>
              <p class="mt-1 text-sm text-error">{@report_name_error}</p>
            <% end %>
          </div>

          <div class="grid grid-cols-1 gap-4 mb-6">
            <div class="ui-fieldset">
              <label for="report-schema-id" class="ui-label-inline">
                <span>Script Schema</span>
                <span
                  class="tooltip tooltip-right cursor-help"
                  data-tip="Limits columns to fields in the selected script."
                  aria-label="Script schema help"
                >
                  <.icon name="hero-question-mark-circle" class="size-4 text-base-content/70" />
                </span>
              </label>
              <select
                id="report-schema-id"
                name="schema_id"
                class="ui-select-plain"
                value={@selected_schema_id}
                phx-target={@myself}
                phx-change="set_schema_id"
              >
                <option value="">Select script schema</option>
                <%= for {label, value} <- schema_id_options(@schema_refs) do %>
                  <option value={value} selected={@selected_schema_id == value}>{label}</option>
                <% end %>
              </select>
            </div>
            <div class="ui-fieldset">
              <label for="report-schema-version" class="ui-label">Schema Version</label>
              <select
                id="report-schema-version"
                name="schema_version"
                class="ui-select-plain"
                value={@selected_schema_version || ""}
                phx-target={@myself}
                phx-change="set_schema_version"
                disabled={@selected_schema_id == @all_scope}
              >
                <option value="">All versions</option>
                <%= for {label, value} <- schema_version_options(@schema_refs, @selected_schema_id) do %>
                  <option value={value} selected={@selected_schema_version == value}>{label}</option>
                <% end %>
              </select>
              <input
                :if={@selected_schema_id == @all_scope}
                type="hidden"
                name="schema_version"
                value=""
              />
            </div>
            <p class="ui-help-text">{schema_scope_hint(@selected_schema_id)}</p>
          </div>

          <%= if @schema_issue do %>
            <p class="text-sm text-error mb-4">{@schema_issue}</p>
          <% end %>

          <!-- Fields Section -->
          <div class="mb-8" data-report-section="columns">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold">Columns (Fields)</h2>
              <button
                id="report-add-column"
                type="button"
                phx-click="add_field"
                phx-target={@myself}
                class="btn btn-sm"
              >
                + Add Column
              </button>
            </div>

            <div class="space-y-3">
              <%= for field <- @fields do %>
                <div
                  data-column-row-id={field.id}
                  class="ui-form-row"
                >
                  <div class="flex-1">
                    <label class="ui-form-label">Schema Field</label>
                    <select
                      id={column_path_select_id(field.id)}
                      name={"fields[#{field.id}][path]"}
                      value={field.path}
                      phx-change="update_field"
                      phx-keydown="schema_field_keydown"
                      phx-target={@myself}
                      phx-value-id={field.id}
                      phx-value-field_id={field.id}
                      class="ui-select-sm"
                    >
                      <option value="">Select schema field</option>
                      <%= for {label, key} <- schema_option_pairs(@schema_options) do %>
                        <option value={key} selected={field.path == key}>{label}</option>
                      <% end %>
                    </select>
                    <p class="mt-1 text-xs text-base-content/60">
                      {column_field_type_hint(schema_option_types(@schema_options), field.path)}
                    </p>
                  </div>
                  <div class="flex-1">
                    <label class="ui-form-label">Column Title</label>
                    <input
                      id={column_title_input_id(field.id)}
                      type="text"
                      phx-hook="ReportColumnTitle"
                      data-last-field={to_string(last_column_field?(@fields, field.id))}
                      name={"fields[#{field.id}][alias]"}
                      value={field.alias}
                      phx-keydown="column_title_keydown"
                      phx-value-id={field.id}
                      phx-blur="update_field"
                      phx-target={@myself}
                      placeholder="Title"
                      class="ui-input-sm"
                    />
                  </div>
                  <%= if length(@fields) > 1 do %>
                    <button
                      type="button"
                      phx-click="remove_field"
                      phx-target={@myself}
                      phx-value-id={field.id}
                      class="mt-6 text-error hover:text-error/80"
                    >
                      <.icon name="hero-trash" class="w-5 h-5" />
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
          <!-- Filters Section -->
          <div class="mb-8" data-report-section="filters">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold">Filters (Optional)</h2>
              <button
                id="report-add-filter"
                type="button"
                phx-click="add_filter"
                phx-target={@myself}
                class="btn btn-sm"
              >
                + Add Filter
              </button>
            </div>

            <div class="space-y-3">
              <%= for filter <- @filters do %>
                <div
                  data-filter-row-id={filter.id}
                  class="ui-form-row"
                >
                  <div class="flex-1">
                    <label class="ui-form-label">Schema Field</label>
                    <select
                      id={filter_field_select_id(filter.id)}
                      name={"filters[#{filter.id}][field]"}
                      value={filter.field}
                      phx-change="update_filter"
                      phx-keydown="filter_field_keydown"
                      phx-target={@myself}
                      phx-value-filter_id={filter.id}
                      class="ui-select-sm"
                    >
                      <option value="">Select schema field</option>
                      <%= for {label, key} <- schema_option_pairs(@schema_options) do %>
                        <option value={key} selected={filter.field == key}>{label}</option>
                      <% end %>
                    </select>
                    <p class="mt-1 text-xs text-base-content/60">
                      {filter_field_type_hint(schema_option_types(@schema_options), filter.field)}
                    </p>
                    <%= if filter_field_hidden?(@fields, filter.field) do %>
                      <div class="mt-2 flex items-center gap-2">
                        <p class="text-xs text-warning">Filtered by hidden field.</p>
                        <button
                          type="button"
                          phx-click="add_filter_field_as_column"
                          phx-target={@myself}
                          phx-value-filter_id={filter.id}
                          class="text-xs font-medium text-primary hover:underline"
                        >
                          Add as column
                        </button>
                      </div>
                    <% end %>
                  </div>
                  <div class="w-32">
                    <label class="ui-form-label">Operator</label>
                    <select
                      id={filter_operator_select_id(filter.id)}
                      name={"filters[#{filter.id}][operator]"}
                      phx-change="update_filter"
                      phx-target={@myself}
                      phx-value-id={filter.id}
                      phx-value-key="operator"
                      class="ui-select-sm"
                    >
                      <option value="=" selected={filter.operator == "="}>=</option>
                      <option value="==" selected={filter.operator == "=="}>==</option>
                      <option value="!=" selected={filter.operator == "!="}>!=</option>
                      <option value=">" selected={filter.operator == ">"}>&gt;</option>
                      <option value=">=" selected={filter.operator == ">="}>&gt;=</option>
                      <option value="<" selected={filter.operator == "<"}>&lt;</option>
                      <option value="<=" selected={filter.operator == "<="}>&lt;=</option>
                    </select>
                  </div>
                  <div class="flex-1">
                    <label class="ui-form-label">
                      {filter_value_label(schema_option_types(@schema_options), filter.field)}
                    </label>
                    <input
                      id={filter_value_input_id(filter.id)}
                      type="text"
                      phx-hook="ReportFilterValue"
                      name={"filters[#{filter.id}][value]"}
                      value={filter.value}
                      phx-change="update_filter"
                      phx-keydown="filter_value_keydown"
                      phx-value-id={filter.id}
                      phx-blur="update_filter"
                      phx-target={@myself}
                      class="ui-input-sm"
                    />
                    <%= if filter_type_error = filter_value_type_error(schema_option_types(@schema_options), filter) do %>
                      <p class="mt-1 text-xs text-error">{filter_type_error}</p>
                    <% end %>
                  </div>
                  <button
                    type="button"
                    phx-click="remove_filter"
                    phx-target={@myself}
                    phx-value-id={filter.id}
                    class="mt-6 text-error hover:text-error/80"
                  >
                    <.icon name="hero-trash" class="w-5 h-5" />
                  </button>
                </div>
              <% end %>
            </div>
          </div>

          <div class="flex justify-end pt-4 border-t border-base-300">
            <.button
              id="report-save-report"
              disabled={
                !report_save_enabled?(
                  @report_name,
                  @report_name_error,
                  @fields,
                  @filters,
                  @schema_options,
                  @schema_error
                )
              }
              phx-disable-with="Saving..."
            >
              Save Report
            </.button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp assign_schema_option_assigns(socket, schema_options),
    do: assign(socket, :schema_options, schema_options)

  defp schema_option_pairs(schema_options), do: Enum.map(schema_options, &{&1.label, &1.key})
  defp schema_option_labels(schema_options), do: Map.new(schema_options, &{&1.key, &1.label})
  defp schema_option_types(schema_options), do: Map.new(schema_options, &{&1.key, &1.value_type})

  defp clear_invalid_selections(socket, schema_options, schema_error) do
    valid_keys = MapSet.new(Enum.map(schema_options, & &1.key))
    old_fields = socket.assigns.fields
    old_filters = socket.assigns.filters
    old_labels = schema_option_labels(socket.assigns.schema_options)

    fields =
      Enum.map(old_fields, &clear_invalid_field_selection(&1, valid_keys, old_labels))

    filters =
      Enum.map(old_filters, &clear_invalid_filter_selection(&1, valid_keys))

    socket
    |> assign_schema_option_assigns(schema_options)
    |> assign(:schema_error, schema_error)
    |> assign(:fields, fields)
    |> assign(:filters, filters)
    |> assign(:schema_issue, schema_issue_for_error(schema_error))
  end

  defp fetch_schema_options(schema_refs, selected_schema_id, selected_schema_version) do
    scoped_refs = refs_for_scope(schema_refs, selected_schema_id, selected_schema_version)

    if scoped_refs == [] do
      {[], :not_found}
    else
      {options, errors} =
        case scoped_refs do
          [ref] ->
            case fetch_ref_options(ref) do
              {:ok, ref_options} -> {[ref_options], []}
              {:error, error} -> {[], [error]}
            end

          _ ->
            case SchemaOptions.options_for_many(scoped_refs, :report) do
              {:ok, %{options: options, errors: errors}} -> {options, errors}
              {:error, error} -> {[], [error]}
            end
        end

      normalized_options = normalize_schema_options(options)
      {normalized_options, schema_error(errors)}
    end
  end

  defp normalize_schema_options(options) do
    options
    |> List.flatten()
    |> Enum.reduce(%{}, fn option, acc ->
      merge_normalized_schema_option(acc, normalize_schema_option(option))
    end)
    |> Map.values()
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  defp clear_invalid_field_selection(field, valid_keys, old_labels) do
    if field.path != "" and not MapSet.member?(valid_keys, field.path) do
      old_default_alias = default_alias_for_key(old_labels, field.path)
      alias_value = if(field.alias == old_default_alias, do: "", else: field.alias)
      %{field | path: "", alias: alias_value}
    else
      field
    end
  end

  defp clear_invalid_filter_selection(filter, valid_keys) do
    if filter.field != "" and not MapSet.member?(valid_keys, filter.field) do
      %{filter | field: ""}
    else
      filter
    end
  end

  defp normalize_schema_option(option) do
    key = Map.get(option, :key)
    label = Map.get(option, :label)
    value_type = Map.get(option, :value_type)

    if is_binary(key) and key != "" do
      %{
        key: key,
        label: if(is_binary(label) and label != "", do: label, else: humanize_field_name(key)),
        value_type: normalize_value_type(value_type)
      }
    else
      nil
    end
  end

  defp merge_normalized_schema_option(acc, nil), do: acc

  defp merge_normalized_schema_option(acc, normalized) do
    Map.update(acc, normalized.key, normalized, fn existing ->
      if existing.value_type == "unknown" and normalized.value_type != "unknown" do
        %{existing | value_type: normalized.value_type}
      else
        existing
      end
    end)
  end

  defp refs_for_scope(schema_refs, @all_scope, _schema_version), do: schema_refs

  defp refs_for_scope(schema_refs, schema_id, schema_version) do
    Enum.filter(schema_refs, fn ref ->
      ref.schema_id == schema_id and
        (schema_version in [nil, ""] or ref.schema_version == schema_version)
    end)
  end

  defp fetch_ref_options(ref) do
    case SchemaOptions.options_for(ref.schema_id, ref.schema_version, :report) do
      {:ok, %{options: options}} when is_list(options) -> {:ok, options}
      {:error, error} -> {:error, error}
    end
  end

  defp schema_error(errors) do
    cond do
      :conflict in errors -> :conflict
      :not_found in errors -> :not_found
      errors != [] -> hd(errors)
      true -> nil
    end
  end

  defp schema_issue_for_error(nil), do: nil
  defp schema_issue_for_error(error), do: SchemaOptions.schema_issue_message(error)

  defp schema_id_options(refs) do
    ids =
      refs
      |> Enum.map(& &1.schema_id)
      |> Enum.uniq()
      |> Enum.sort()

    [{"All Script Schemas", @all_scope} | Enum.map(ids, &{&1, &1})]
  end

  defp schema_version_options(refs, schema_id) do
    refs
    |> Enum.filter(&(&1.schema_id == schema_id))
    |> Enum.map(& &1.schema_version)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&{&1, &1})
  end

  defp first_schema_version(_refs, @all_scope), do: nil

  defp first_schema_version(refs, schema_id) do
    refs
    |> Enum.find(&(&1.schema_id == schema_id))
    |> then(&if(&1, do: &1.schema_version, else: nil))
  end

  defp filter_value_label(_option_types, field) when field in [nil, ""], do: "Value"

  defp filter_value_label(option_types, field) do
    case Map.get(option_types, field) do
      type when is_binary(type) and type != "" -> "Value (#{type})"
      _ -> "Value"
    end
  end

  defp schema_scope_hint(@all_scope),
    do: "Using common script fields across all products."

  defp schema_scope_hint(schema_id) when is_binary(schema_id),
    do: "Scope limited to #{schema_id}."

  defp schema_scope_hint(_), do: "Using common script fields across all products."

  defp column_field_type_hint(_option_types, field) when field in [nil, ""],
    do: "Select a field to see its type."

  defp column_field_type_hint(option_types, field) do
    case Map.get(option_types, field) do
      type when is_binary(type) and type != "" -> "Type: #{type}"
      _ -> "Type: unknown"
    end
  end

  defp filter_field_type_hint(_option_types, field) when field in [nil, ""],
    do: "Select a field to see its type."

  defp filter_field_type_hint(option_types, field) do
    case Map.get(option_types, field) do
      type when is_binary(type) and type != "" -> "Field type: #{type}"
      _ -> "Field type: unknown"
    end
  end

  defp filter_field_hidden?(_fields, filter_field) when filter_field in [nil, ""], do: false

  defp filter_field_hidden?(fields, filter_field)
       when is_list(fields) and is_binary(filter_field) do
    not Enum.any?(fields, &(&1.path == filter_field))
  end

  defp filter_field_hidden?(_fields, _filter_field), do: false

  defp update_field_entry(field, :path, value, option_labels) do
    if field.path == value do
      field
    else
      new_default_alias = default_alias_for_key(option_labels, value)
      %{field | path: value, alias: new_default_alias}
    end
  end

  defp update_field_entry(field, :alias, value, _option_labels) do
    %{field | alias: value}
  end

  defp default_alias_for_key(_option_labels, key) when key in [nil, ""], do: ""

  defp default_alias_for_key(option_labels, key) do
    Map.get(option_labels, key, humanize_field_name(key))
  end

  defp humanize_field_name(key) when is_binary(key) do
    key
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize_field_name(_), do: ""

  defp validate_selected_keys(fields, filters, schema_options) do
    valid_keys = MapSet.new(Enum.map(schema_options, & &1.key))

    invalid_slot_ids =
      Enum.flat_map(fields, fn field ->
        if present?(field.path) and not MapSet.member?(valid_keys, field.path),
          do: [field.id],
          else: []
      end) ++
        Enum.flat_map(filters, fn filter ->
          if present?(filter.field) and not MapSet.member?(valid_keys, filter.field),
            do: [filter.id],
            else: []
        end)

    %{
      valid: Enum.empty?(invalid_slot_ids),
      issues: [],
      cleared_slot_ids: Enum.uniq(invalid_slot_ids)
    }
  end

  defp persisted_schema_id(@all_scope), do: nil
  defp persisted_schema_id(schema_id), do: schema_id

  defp persisted_schema_version(@all_scope, _schema_version), do: nil
  defp persisted_schema_version(_schema_id, schema_version), do: schema_version

  defp normalize_explicit_schema_version(value, _default) when value in [nil, ""], do: nil

  defp normalize_explicit_schema_version(value, default),
    do: normalize_scope_value(value, default)

  defp normalize_scope_value(value, default) when value in [nil, ""], do: default
  defp normalize_scope_value(value, _default), do: value

  defp normalize_value_type(type) when is_binary(type) and type != "", do: type
  defp normalize_value_type(_), do: "unknown"

  defp extract_event_value(%{"value" => value}) when is_binary(value) do
    cond do
      value == "" ->
        ""

      String.contains?(value, "=") ->
        case URI.decode_query(value) do
          decoded when is_map(decoded) and map_size(decoded) > 0 ->
            Map.get(decoded, "value", value)

          _ ->
            value
        end

      true ->
        value
    end
  rescue
    ArgumentError -> value
  end

  defp extract_event_value(%{"value" => value}) when is_atom(value), do: Atom.to_string(value)

  defp extract_event_value(%{"value" => value}) when is_integer(value),
    do: Integer.to_string(value)

  defp extract_event_value(%{"value" => value}) when is_float(value), do: Float.to_string(value)
  defp extract_event_value(%{"value" => value}) when is_boolean(value), do: to_string(value)
  defp extract_event_value(_), do: ""

  defp blank?(value), do: value in [nil, ""]
  defp present?(value), do: not blank?(value)

  defp report_save_enabled?(name, name_error, fields, filters, schema_options, schema_error) do
    option_types = Map.new(schema_options, &{&1.key, &1.value_type})
    validation = validate_selected_keys(fields, filters, schema_options)

    present?(name) and is_nil(name_error) and is_nil(schema_error) and
      Enum.all?(fields, &present?(&1.path)) and
      Enum.all?(filters, &valid_filter_row?(&1, option_types)) and
      validation.valid
  end

  defp valid_filter_row?(%{field: field, value: value} = filter, option_types) do
    cond do
      blank?(field) and blank?(value) -> true
      present?(field) and present?(value) -> is_nil(filter_value_type_error(option_types, filter))
      true -> false
    end
  end

  defp valid_filter_row?(_filter, _option_types), do: false

  defp filters_have_invalid_value_types?(filters, option_types) do
    Enum.any?(filters, fn filter -> not is_nil(filter_value_type_error(option_types, filter)) end)
  end

  defp filter_value_type_error(_option_types, %{field: field, value: value})
       when field in [nil, ""] or value in [nil, ""] do
    nil
  end

  defp filter_value_type_error(option_types, %{field: field, value: value})
       when is_binary(field) and is_binary(value) do
    value_type = option_types |> Map.get(field, "unknown") |> normalize_value_type()
    normalized_value = String.trim(value)

    if normalized_value == "" do
      nil
    else
      validation_message_for_value_type(value_type, normalized_value)
    end
  end

  defp filter_value_type_error(_option_types, _filter), do: nil

  defp validation_message_for_value_type("integer", value),
    do: invalid_message(valid_integer?(value), "Expected integer value.")

  defp validation_message_for_value_type("number", value),
    do: invalid_message(valid_number?(value), "Expected numeric value.")

  defp validation_message_for_value_type("float", value),
    do: invalid_message(valid_number?(value), "Expected numeric value.")

  defp validation_message_for_value_type("boolean", value),
    do: invalid_message(valid_boolean?(value), "Expected boolean (true/false).")

  defp validation_message_for_value_type("object", value),
    do: invalid_message(valid_json_object?(value), "Expected JSON object.")

  defp validation_message_for_value_type("array", value),
    do: invalid_message(valid_json_array?(value), "Expected JSON array.")

  defp validation_message_for_value_type(_, _value), do: nil

  defp invalid_message(true, _message), do: nil
  defp invalid_message(false, message), do: message

  defp valid_integer?(value) when is_binary(value) do
    case Integer.parse(value) do
      {_int, ""} -> true
      _ -> false
    end
  end

  defp valid_integer?(_value), do: false

  defp valid_number?(value) when is_binary(value) do
    case Float.parse(value) do
      {_float, ""} -> true
      _ -> false
    end
  end

  defp valid_number?(_value), do: false

  defp valid_boolean?(value) when is_binary(value) do
    String.downcase(String.trim(value)) in ["true", "false"]
  end

  defp valid_boolean?(_value), do: false

  defp valid_json_object?(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> is_map(decoded)
      _ -> false
    end
  end

  defp valid_json_object?(_value), do: false

  defp valid_json_array?(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> is_list(decoded)
      _ -> false
    end
  end

  defp valid_json_array?(_value), do: false

  defp maybe_record_invalid_attempt(%{valid: true}), do: :ok

  defp maybe_record_invalid_attempt(_validation) do
    :telemetry.execute(
      [:nixstasis, :builder, :invalid_save_attempt],
      %{count: 1},
      %{builder: "report"}
    )
  end

  defp maybe_record_first_attempt(fields, filters) do
    if Enum.all?(fields, &(&1.path != "")) and
         Enum.all?(filters, &(&1.field != "" or &1.value == "")) do
      :telemetry.execute(
        [:nixstasis, :builder, :first_attempt_success],
        %{count: 1},
        %{builder: "report"}
      )
    end
  end

  defp safe_field_key("path"), do: :path
  defp safe_field_key("alias"), do: :alias
  defp safe_field_key(_), do: nil

  defp safe_filter_key("field"), do: :field
  defp safe_filter_key("operator"), do: :operator
  defp safe_filter_key("value"), do: :value
  defp safe_filter_key(_), do: nil

  defp ensure_minimum_one_field([], previous_fields), do: previous_fields
  defp ensure_minimum_one_field(fields, _previous_fields), do: fields

  defp maybe_focus_column_title_input(socket, :path, id, value, current_path)
       when is_binary(id) and is_binary(value) do
    if value == "" or value == current_path do
      socket
    else
      push_event(socket, "focus_column_title", %{id: column_title_input_id(id)})
    end
  end

  defp maybe_focus_column_title_input(socket, _field_key, _id, _value, _current_path), do: socket

  defp column_title_input_id(id), do: "report-field-alias-#{id}"
  defp column_path_select_id(id), do: "report-field-path-#{id}"
  defp filter_field_select_id(id), do: "report-filter-field-#{id}"
  defp filter_operator_select_id(id), do: "report-filter-operator-#{id}"
  defp filter_value_input_id(id), do: "report-filter-value-#{id}"

  defp last_column_field?(fields, id) when is_list(fields) and is_binary(id) do
    case List.last(fields) do
      %{id: last_id} -> last_id == id
      _ -> false
    end
  end

  defp last_column_field?(_fields, _id), do: false

  defp current_field_path(fields, id) when is_binary(id) do
    fields
    |> Enum.find(&(&1.id == id))
    |> case do
      %{path: path} when is_binary(path) -> path
      _ -> nil
    end
  end

  defp current_field_path(_fields, _id), do: nil

  defp handle_column_title_keydown(socket, id, key) when is_binary(key) do
    case String.downcase(key) do
      "enter" ->
        advance_column_flow(socket, id)

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_column_title_keydown(socket, _id, _key), do: {:noreply, socket}

  defp advance_column_flow(socket, id) do
    fields = socket.assigns.fields

    case next_column_field_id(fields, id) do
      nil ->
        new_field = %{id: Ecto.UUID.generate(), path: "", alias: ""}
        new_fields = fields ++ [new_field]

        {:noreply,
         socket
         |> assign(:fields, new_fields)
         |> assign(:recent_enter_added_field_id, new_field.id)
         |> push_event("focus_schema_field", %{id: column_path_select_id(new_field.id)})}

      next_id ->
        {:noreply, push_event(socket, "focus_schema_field", %{id: column_path_select_id(next_id)})}
    end
  end

  defp next_column_field_id(fields, id) do
    with index when is_integer(index) <- Enum.find_index(fields, &(&1.id == id)),
         true <- index < length(fields) - 1,
         %{id: next_id} <- Enum.at(fields, index + 1) do
      next_id
    else
      _ -> nil
    end
  end

  defp update_report_field(socket, %{"id" => id, "key" => key} = params) do
    value = extract_event_value(params)
    field_key = safe_field_key(key)
    current_path = current_field_path(socket.assigns.fields, id)

    fields =
      Enum.map(socket.assigns.fields, fn field ->
        if field.id == id and field_key do
          update_field_entry(field, field_key, value, schema_option_labels(socket.assigns.schema_options))
        else
          field
        end
      end)

    socket =
      socket
      |> assign(:fields, fields)
      |> maybe_clear_recent_enter_added_field(id, value)
      |> maybe_focus_column_title_input(field_key, id, value, current_path)

    {:noreply, socket}
  end

  defp update_report_filter(socket, %{"id" => id, "key" => key} = params) do
    value = extract_event_value(params)
    filter_key = safe_filter_key(key)
    current_field = current_filter_field(socket.assigns.filters, id)
    current_operator = current_filter_operator(socket.assigns.filters, id)

    filters =
      Enum.map(socket.assigns.filters, fn filter ->
        if filter.id == id and filter_key, do: Map.put(filter, filter_key, value), else: filter
      end)

    socket =
      socket
      |> assign(:filters, filters)
      |> maybe_focus_filter_operator(filter_key, id, value, current_field)
      |> maybe_focus_filter_value(filter_key, id, value, current_operator)

    {:noreply, socket}
  end

  defp parse_field_event_params(params) do
    parse_nested_event_params(params, "fields", &safe_field_key/1)
  end

  defp parse_filter_event_params(params) do
    parse_nested_event_params(params, "filters", &safe_filter_key/1)
  end

  defp parse_nested_event_params(%{"_target" => [root, id, key]} = params, root, key_parser) do
    case key_parser.(key) do
      nil ->
        :error

      parsed_key ->
        value =
          params
          |> Map.get(root, %{})
          |> Map.get(id, %{})
          |> Map.get(key, "")
          |> normalize_nested_value()

        {:ok, id, parsed_key, value}
    end
  end

  defp parse_nested_event_params(%{"_target" => [target]} = params, root, key_parser) do
    target_regex = ~r/^#{root}\[([^\]]+)\]\[([^\]]+)\]$/

    case Regex.run(target_regex, target) do
      [_, id, key] ->
        normalized = Map.put(params, "_target", [root, id, key])
        parse_nested_event_params(normalized, root, key_parser)

      _ ->
        :error
    end
  end

  defp parse_nested_event_params(_params, _root, _key_parser), do: :error

  defp normalize_nested_value(value) when is_binary(value), do: value
  defp normalize_nested_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_nested_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_nested_value(value) when is_float(value), do: Float.to_string(value)
  defp normalize_nested_value(value) when is_boolean(value), do: to_string(value)
  defp normalize_nested_value(_value), do: ""

  defp maybe_focus_first_column_field(socket, %{action: :edit}, fields) when is_list(fields) do
    case List.first(fields) do
      %{id: id} when is_binary(id) ->
        push_event(socket, "focus_schema_field", %{id: column_path_select_id(id)})

      _ ->
        socket
    end
  end

  defp maybe_focus_first_column_field(socket, _assigns, _fields), do: socket

  defp submitted_fields_from_params(params, existing_fields, option_labels) do
    existing_by_id = Map.new(existing_fields, &{&1.id, &1})
    submitted_fields = Map.get(params, "fields")

    if is_map(submitted_fields) do
      ordered_ids = Enum.map(existing_fields, & &1.id)

      extra_ids =
        submitted_fields |> Map.keys() |> Enum.reject(&(&1 in ordered_ids)) |> Enum.sort()

      (ordered_ids ++ extra_ids)
      |> Enum.map(fn id ->
        submitted = Map.get(submitted_fields, id, %{})
        existing = Map.get(existing_by_id, id, %{id: id, path: "", alias: ""})
        path = normalize_nested_value(Map.get(submitted, "path", existing.path))

        alias_value =
          normalize_nested_value(Map.get(submitted, "alias", default_alias_for_key(option_labels, path)))

        %{
          id: id,
          path: path,
          alias: alias_value
        }
      end)
    else
      existing_fields
    end
  end

  defp submitted_filters_from_params(params, existing_filters) do
    existing_by_id = Map.new(existing_filters, &{&1.id, &1})
    submitted_filters = Map.get(params, "filters")

    if is_map(submitted_filters) do
      ordered_ids = Enum.map(existing_filters, & &1.id)

      extra_ids =
        submitted_filters |> Map.keys() |> Enum.reject(&(&1 in ordered_ids)) |> Enum.sort()

      (ordered_ids ++ extra_ids)
      |> Enum.map(fn id ->
        submitted = Map.get(submitted_filters, id, %{})
        existing = Map.get(existing_by_id, id, %{id: id, field: "", operator: "=", value: ""})

        %{
          id: id,
          field: normalize_nested_value(Map.get(submitted, "field", existing.field)),
          operator:
            normalize_filter_operator(normalize_nested_value(Map.get(submitted, "operator", existing.operator))),
          value: normalize_nested_value(Map.get(submitted, "value", existing.value))
        }
      end)
    else
      existing_filters
    end
  end

  defp maybe_clear_recent_enter_added_field(socket, id, value) do
    if socket.assigns.recent_enter_added_field_id == id and present?(value) do
      assign(socket, :recent_enter_added_field_id, nil)
    else
      socket
    end
  end

  defp maybe_remove_field_row(socket, id, key) when is_binary(key) do
    case String.downcase(key) do
      "delete" -> remove_field_row(socket, id)
      "backspace" -> remove_field_row(socket, id)
      _ -> {:noreply, socket}
    end
  end

  defp maybe_remove_field_row(socket, _id, _key), do: {:noreply, socket}

  defp normalize_report_name(value) when is_binary(value), do: String.trim(value)
  defp normalize_report_name(_), do: ""

  defp maybe_validate_report_name(socket, params, name) do
    should_validate =
      case socket.assigns.report do
        %{id: nil} -> true
        _ -> report_name_changed?(params)
      end

    if should_validate do
      cond do
        name == "" ->
          assign(socket, :report_name_error, nil)

        name_taken_for_other_report?(socket.assigns.report, name) ->
          assign(socket, :report_name_error, "Report title is already used.")

        true ->
          assign(socket, :report_name_error, nil)
      end
    else
      socket
    end
  end

  defp report_name_changed?(%{"_target" => target}) when is_list(target) do
    Enum.any?(target, &(&1 == "name"))
  end

  defp report_name_changed?(%{"name" => _} = params), do: map_size(params) == 1

  defp report_name_changed?(_), do: false

  defp duplicate_report_name_error?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, fn error ->
      field = Map.get(error, :field)
      validation = Map.get(error, :validation)
      message = Map.get(error, :message, "")
      context = Map.get(error, :context, %{})

      field == :name and
        (validation == :unique or
           String.contains?(String.downcase(to_string(message)), "unique") or
           Map.get(context, :constraint) == "custom_reports_unique_name_index")
    end)
  end

  defp duplicate_report_name_error?(_), do: false

  defp remove_field_row(socket, id) do
    fields = socket.assigns.fields

    cond do
      length(fields) <= 1 ->
        {:noreply, socket}

      not Enum.any?(fields, &(&1.id == id)) ->
        {:noreply, socket}

      true ->
        {updated_fields, focus_id} = remove_field_and_focus_target(fields, id)

        socket =
          socket
          |> assign(:fields, updated_fields)
          |> assign(:recent_enter_added_field_id, nil)

        socket =
          if is_binary(focus_id) do
            push_event(socket, "focus_column_title", %{id: column_title_input_id(focus_id)})
          else
            socket
          end

        {:noreply, socket}
    end
  end

  defp remove_field_and_focus_target(fields, id) do
    index = Enum.find_index(fields, &(&1.id == id))
    updated_fields = Enum.reject(fields, &(&1.id == id))

    focus_id =
      if is_integer(index) and index > 0 do
        field_id_at(updated_fields, index - 1)
      else
        field_id_at(updated_fields, 0)
      end

    {updated_fields, focus_id}
  end

  defp field_id_at(fields, index) do
    fields
    |> Enum.at(index)
    |> case do
      %{id: field_id} -> field_id
      _ -> nil
    end
  end

  defp clear_recent_enter_added_field(socket, id) do
    if socket.assigns.recent_enter_added_field_id == id do
      assign(socket, :recent_enter_added_field_id, nil)
    else
      socket
    end
  end

  defp add_filter_field_as_column(socket, filter_id) when is_binary(filter_id) do
    case Enum.find(socket.assigns.filters, &(&1.id == filter_id)) do
      %{field: filter_field} when is_binary(filter_field) and filter_field != "" ->
        case field_id_for_path(socket.assigns.fields, filter_field) do
          nil ->
            add_column_for_filter_field(socket, filter_field)

          existing_field_id ->
            {:noreply,
             push_event(socket, "focus_column_title", %{
               id: column_title_input_id(existing_field_id)
             })}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp add_filter_field_as_column(socket, _filter_id), do: {:noreply, socket}

  defp add_column_for_filter_field(socket, filter_field) do
    new_field = %{
      id: Ecto.UUID.generate(),
      path: filter_field,
      alias: default_alias_for_key(schema_option_labels(socket.assigns.schema_options), filter_field)
    }

    fields = socket.assigns.fields ++ [new_field]

    {:noreply,
     socket
     |> assign(:fields, fields)
     |> assign(:recent_enter_added_field_id, nil)
     |> push_event("focus_column_title", %{id: column_title_input_id(new_field.id)})}
  end

  defp field_id_for_path(fields, path) when is_list(fields) and is_binary(path) do
    fields
    |> Enum.find(&(&1.path == path))
    |> case do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp field_id_for_path(_fields, _path), do: nil

  defp current_filter_field(filters, id) when is_binary(id) do
    filters
    |> Enum.find(&(&1.id == id))
    |> case do
      %{field: field} when is_binary(field) -> field
      _ -> nil
    end
  end

  defp current_filter_field(_filters, _id), do: nil

  defp current_filter_operator(filters, id) when is_binary(id) do
    filters
    |> Enum.find(&(&1.id == id))
    |> case do
      %{operator: operator} when is_binary(operator) -> operator
      _ -> nil
    end
  end

  defp current_filter_operator(_filters, _id), do: nil

  defp maybe_focus_filter_operator(socket, :field, id, value, current_field)
       when is_binary(id) and is_binary(value) do
    if value == "" or value == current_field do
      socket
    else
      push_event(socket, "focus_filter_operator", %{id: filter_operator_select_id(id)})
    end
  end

  defp maybe_focus_filter_operator(socket, _key, _id, _value, _current_field), do: socket

  defp maybe_focus_filter_value(socket, :operator, id, value, current_operator)
       when is_binary(id) and is_binary(value) do
    if value == "" or value == current_operator do
      socket
    else
      push_event(socket, "focus_filter_value", %{id: filter_value_input_id(id)})
    end
  end

  defp maybe_focus_filter_value(socket, _key, _id, _value, _current_operator), do: socket

  defp handle_filter_value_keydown(socket, _id, key) when is_binary(key) do
    case String.downcase(key) do
      "enter" ->
        add_filter_row_and_focus(socket)

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_filter_value_keydown(socket, _id, _key), do: {:noreply, socket}

  defp add_filter_row_and_focus(socket) do
    new_filter = %{id: Ecto.UUID.generate(), field: "", operator: "=", value: ""}
    filters = socket.assigns.filters ++ [new_filter]

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> push_event("focus_filter_field", %{id: filter_field_select_id(new_filter.id)})}
  end

  defp maybe_remove_filter_row(socket, id, key) when is_binary(key) do
    case String.downcase(key) do
      "delete" -> remove_filter_row(socket, id)
      "backspace" -> remove_filter_row(socket, id)
      _ -> {:noreply, socket}
    end
  end

  defp maybe_remove_filter_row(socket, _id, _key), do: {:noreply, socket}

  defp remove_filter_row(socket, id) do
    remove_filter_and_focus(socket, id)
  end

  defp remove_filter_and_focus(socket, id) when is_binary(id) do
    filters = socket.assigns.filters
    index = Enum.find_index(filters, &(&1.id == id))

    if is_integer(index) do
      updated_filters = Enum.reject(filters, &(&1.id == id))

      socket =
        socket
        |> assign(:filters, updated_filters)
        |> focus_after_filter_delete(updated_filters, index)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp remove_filter_and_focus(socket, _id), do: {:noreply, socket}

  defp focus_after_filter_delete(socket, updated_filters, deleted_index) do
    previous_index = deleted_index - 1

    cond do
      previous_index >= 0 and previous_index < length(updated_filters) ->
        case Enum.at(updated_filters, previous_index) do
          %{id: previous_id} ->
            push_event(socket, "focus_filter_value", %{id: filter_value_input_id(previous_id)})

          _ ->
            focus_last_column_title(socket)
        end

      updated_filters != [] ->
        case Enum.at(updated_filters, 0) do
          %{id: remaining_id} ->
            push_event(socket, "focus_filter_value", %{id: filter_value_input_id(remaining_id)})

          _ ->
            focus_last_column_title(socket)
        end

      true ->
        focus_last_column_title(socket)
    end
  end

  defp focus_last_column_title(socket) do
    case List.last(socket.assigns.fields) do
      %{id: field_id} ->
        push_event(socket, "focus_column_title", %{id: column_title_input_id(field_id)})

      _ ->
        socket
    end
  end
end
