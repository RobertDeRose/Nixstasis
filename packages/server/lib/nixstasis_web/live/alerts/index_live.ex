defmodule NixstasisWeb.AlertLive.Index do
  use NixstasisWeb, :live_view

  require Ash.Query

  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.Alert
  alias Nixstasis.Monitoring.AlertRule
  alias Nixstasis.SchemaOptions

  @success_flash_timeout_ms 3_000

  def mount(_params, _session, socket) do
    alerts =
      Alert
      |> Ash.Query.sort(triggered_at: :desc)
      |> Ash.Query.load(:device)
      |> Ash.read!(domain: Domain)

    {:ok,
     socket
     |> assign(:alerts, alerts)
     |> assign(:rule_filters, %{"query" => ""})
     |> assign(:rule_sort_by, "product_name")
     |> assign(:rule_sort_dir, "asc")
     |> assign(:alerts_tab, "active")
     |> assign_rules(Domain.list_rules!())
     |> assign(:form, nil)
     |> assign(:schema_refs, [])
     |> assign(:selected_schema_id, nil)
     |> assign(:selected_schema_version, nil)
     |> assign(:schema_options, [])
     |> assign(:schema_option_types, %{})
     |> assign(:schema_issue, nil)
     |> assign(:rule_dirty?, false)
     |> assign(:rule_initial_draft, %{})
     |> assign(:rule_editing, nil)
     |> assign(:rule_edit_blocked_reason, nil)
     |> assign(:rule_to_delete, nil)
     |> assign(:show_discard_confirm, false)
     |> assign(:no_schema_fields_message, nil)
     |> assign(:modal_focus_id, "alert-schema-id")
     |> assign(:success_flash_generation, 0)}
  end

  def handle_params(params, _url, socket) do
    tab =
      case socket.assigns.live_action do
        action when action in [:new, :edit] -> "rules"
        _ -> normalize_tab(Map.get(params, "tab"))
      end

    {:noreply,
     socket
     |> assign(:alerts_tab, tab)
     |> apply_action(socket.assigns.live_action, params)}
  end

  def handle_event("validate_rule", params, socket) do
    {schema_id, schema_version, rule_params} = normalize_rule_payload(params, socket)

    {schema_options, schema_option_types} =
      fetch_schema_option_metadata(schema_id, schema_version)

    no_schema_fields_message = no_schema_fields_message(schema_id, schema_options)

    edit_blocked? =
      socket.assigns.live_action == :edit and present?(socket.assigns.rule_edit_blocked_reason)

    condition_field = Map.get(rule_params, "condition_field", "")
    valid_field? = Enum.any?(schema_options, fn {_label, value} -> value == condition_field end)

    normalized_params =
      if edit_blocked? do
        rule_params
        |> Map.put("product_name", schema_id || "")
        |> normalize_operator_for_field(schema_option_types)
      else
        rule_params
        |> Map.put("product_name", schema_id || "")
        |> maybe_clear_invalid_condition_field(condition_field, valid_field?)
        |> normalize_operator_for_field(schema_option_types)
      end

    form = AshPhoenix.Form.validate(socket.assigns.form, normalized_params)

    issues =
      if edit_blocked?,
        do: [],
        else: AlertRule.validation_issues(schema_option_types, normalized_params)

    draft = draft_state_from(schema_id, schema_version, normalized_params)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:selected_schema_id, schema_id)
     |> assign(:selected_schema_version, schema_version)
     |> assign(:schema_options, schema_options)
     |> assign(:schema_option_types, schema_option_types)
     |> assign(
       :schema_issue,
       if(edit_blocked?, do: nil, else: schema_issue(condition_field, valid_field?, issues))
     )
     |> assign(:no_schema_fields_message, no_schema_fields_message)
     |> assign(:rule_dirty?, dirty_draft?(socket.assigns.rule_initial_draft, draft))
     |> assign(:show_discard_confirm, false)}
  end

  def handle_event("save_rule", params, socket) do
    {schema_id, schema_version, rule_params} = normalize_rule_payload(params, socket)
    operator = Map.get(rule_params, "operator")
    threshold_value = Map.get(rule_params, "threshold_value")

    no_changes_to_save? =
      socket.assigns.live_action == :edit and
        not edit_rule_values_changed?(
          socket.assigns.rule_editing,
          rule_params["condition_field"],
          operator,
          threshold_value
        )

    if no_changes_to_save? do
      {:noreply, socket |> assign(:schema_issue, nil)}
    else
      validation =
        SchemaOptions.validate_selections(:alert, schema_id || "", schema_version || "", [
          %{"slot_id" => "condition_field", "selected_key" => rule_params["condition_field"]}
        ])

      {schema_options, schema_option_types} =
        fetch_schema_option_metadata(schema_id, schema_version)

      rule_params = normalize_operator_for_field(rule_params, schema_option_types)
      issues = AlertRule.validation_issues(schema_option_types, rule_params)
      no_schema_fields_message = no_schema_fields_message(schema_id, schema_options)

      save_rule_result(socket, %{
        schema_id: schema_id,
        schema_version: schema_version,
        schema_options: schema_options,
        schema_option_types: schema_option_types,
        no_schema_fields_message: no_schema_fields_message,
        validation: validation,
        issues: issues,
        rule_params: rule_params,
        rule_edit_blocked_reason: socket.assigns.rule_edit_blocked_reason
      })
    end
  end

  def handle_event("request_close_rule_modal", _params, socket) do
    if socket.assigns.rule_dirty? do
      {:noreply, assign(socket, :show_discard_confirm, true)}
    else
      {:noreply, push_patch(socket, to: ~p"/alerts?tab=rules")}
    end
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    handle_event("request_close_rule_modal", %{}, socket)
  end

  def handle_event("cancel_discard_rule_changes", _params, socket) do
    {:noreply, assign(socket, :show_discard_confirm, false)}
  end

  def handle_event("confirm_discard_rule_changes", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_discard_confirm, false)
     |> push_patch(to: ~p"/alerts?tab=rules")}
  end

  def handle_event("edit_rule", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/alerts/#{id}/edit?tab=rules")}
  end

  def handle_event("confirm_delete_rule", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(to_string(&1.id) == to_string(id)))
    {:noreply, assign(socket, :rule_to_delete, rule)}
  end

  def handle_event("cancel_delete_rule", _params, socket) do
    {:noreply, assign(socket, :rule_to_delete, nil)}
  end

  def handle_event("delete_rule", _params, socket) do
    case socket.assigns.rule_to_delete do
      nil ->
        {:noreply, put_flash(socket, :error, "Unable to delete rule")}

      rule ->
        case Domain.destroy_rule(rule.rule) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign_rules(Domain.list_rules!())
             |> assign(:rule_to_delete, nil)
             |> put_flash(:info, "Rule deleted")}

          %AlertRule{} ->
            {:noreply,
             socket
             |> assign_rules(Domain.list_rules!())
             |> assign(:rule_to_delete, nil)
             |> put_flash(:info, "Rule deleted")}

          :ok ->
            {:noreply,
             socket
             |> assign_rules(Domain.list_rules!())
             |> assign(:rule_to_delete, nil)
             |> put_flash(:info, "Rule deleted")}

          _ ->
            {:noreply, put_flash(socket, :error, "Unable to delete rule")}
        end
    end
  end

  def handle_event("select_alerts_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/alerts?tab=#{normalize_tab(tab)}")}
  end

  def handle_event("set_rule_sort", %{"by" => by}, socket) do
    sort_by =
      if by in ~w(name product_name condition_field operator updated_at), do: by, else: "product_name"

    sort_dir =
      if socket.assigns.rule_sort_by == sort_by and socket.assigns.rule_sort_dir == "asc",
        do: "desc",
        else: "asc"

    {:noreply,
     socket
     |> assign(:rule_sort_by, sort_by)
     |> assign(:rule_sort_dir, sort_dir)
     |> apply_rule_filters()}
  end

  def handle_event("update_rule_filters", %{"filters" => filters}, socket) do
    merged =
      socket.assigns.rule_filters
      |> Map.merge(filters)
      |> Map.update("query", "", &String.trim/1)

    {:noreply,
     socket
     |> assign(:rule_filters, merged)
     |> apply_rule_filters()}
  end

  def handle_event("clear_rule_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:rule_filters, %{"query" => ""})
     |> assign(:rule_sort_by, "product_name")
     |> assign(:rule_sort_dir, "asc")
     |> apply_rule_filters()}
  end

  def handle_info({:clear_flash, key, generation}, socket) do
    if socket.assigns.success_flash_generation == generation do
      {:noreply, clear_flash(socket, key)}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="ui-page-shell">
      <.header>
        Alerts
        <:subtitle>System notifications and device alerts</:subtitle>
        <:actions>
          <.link :if={@alerts_tab == "rules"} patch={~p"/alerts/new?tab=rules"}>
            <.button>Add Rule</.button>
          </.link>
        </:actions>
      </.header>

      <div role="tablist" class="tabs tabs-boxed mt-6 mb-4 w-fit">
        <button
          role="tab"
          type="button"
          phx-click="select_alerts_tab"
          phx-value-tab="active"
          class={["tab", @alerts_tab == "active" && "tab-active"]}
        >
          Active Alerts
        </button>
        <button
          role="tab"
          type="button"
          phx-click="select_alerts_tab"
          phx-value-tab="rules"
          class={["tab", @alerts_tab == "rules" && "tab-active"]}
        >
          Edit Alert Rules
        </button>
      </div>

      <div :if={@alerts_tab == "active"}>
        <.table id="alerts" rows={@alerts}>
          <:col :let={alert} label="Type">
            <span class={["badge", alert.type == :offline && "badge-error"]}>{alert.type}</span>
          </:col>
          <:col :let={alert} label="Device">
            {if alert.device, do: alert.device.mac_address, else: "-"}
          </:col>
          <:col :let={alert} label="Message">{alert.message}</:col>
          <:col :let={alert} label="Time">{alert.triggered_at}</:col>
          <:col :let={alert} label="Status">{alert.status}</:col>
        </.table>
      </div>

      <div :if={@alerts_tab == "rules"} class="mt-2 ui-card-panel">
        <div class="card-body p-0">
          <div class="grid grid-cols-1 gap-3 border-b border-base-300 p-4 lg:grid-cols-[1fr_auto] lg:items-end">
            <form phx-change="update_rule_filters" class="w-full">
              <label class="ui-label-strong">
                Filter rules
              </label>
              <input
                type="text"
                name="filters[query]"
                value={@rule_filters["query"]}
                class="ui-input-sm"
                placeholder="Filter by rule name, schema product, field, operator, or threshold"
              />
            </form>
            <button type="button" phx-click="clear_rule_filters" class="btn btn-sm btn-ghost">
              Clear
            </button>
          </div>

          <div class="overflow-x-auto">
            <table class="table table-zebra table-fixed">
              <thead>
                <tr>
                  <th class="w-[45%] min-w-[16rem]">
                    <button type="button" phx-click="set_rule_sort" phx-value-by="name" class="link link-hover">
                      Rule {sort_indicator(@rule_sort_by, @rule_sort_dir, "name")}
                    </button>
                  </th>
                  <th class="w-[35%]">
                    <button type="button" phx-click="set_rule_sort" phx-value-by="condition_field" class="link link-hover">
                      Condition {sort_indicator(@rule_sort_by, @rule_sort_dir, "condition_field")}
                    </button>
                  </th>
                  <th class="w-[10%]">
                    <button type="button" phx-click="set_rule_sort" phx-value-by="operator" class="link link-hover">
                      Operator {sort_indicator(@rule_sort_by, @rule_sort_dir, "operator")}
                    </button>
                  </th>
                  <th class="w-[10%]">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={rule <- @rules}>
                  <td class="w-[45%] min-w-[16rem]">
                    <div class="grid grid-cols-[6rem_minmax(0,1fr)] items-center gap-2">
                      <%= if rule.edit_disabled_reason do %>
                        <span
                          class="tooltip tooltip-right inline-flex w-24 justify-start"
                          data-tip={rule.edit_disabled_reason}
                        >
                          <span class="badge badge-warning badge-xs">Deprecated</span>
                        </span>
                      <% else %>
                        <span class="inline-flex w-24"></span>
                      <% end %>
                      <span class="truncate">
                        <span class="block font-semibold">{rule.name}</span>
                        <span class="block text-xs text-base-content/60">{rule.product_name}</span>
                      </span>
                    </div>
                  </td>
                  <td class="w-[35%]">
                    <span class="badge badge-ghost badge-sm">{rule.condition_field}</span>
                    <span class="ml-2 text-base-content/80">{rule.threshold_value}</span>
                  </td>
                  <td class="w-[10%] font-semibold">{rule.operator}</td>
                  <td class="w-[10%]">
                    <div class="grid grid-cols-[1.5rem_1.5rem] items-center gap-2">
                      <%= if is_nil(rule.edit_disabled_reason) do %>
                        <button
                          type="button"
                          phx-click="edit_rule"
                          phx-value-id={rule.id}
                          class="btn btn-ghost btn-xs px-1 text-info hover:bg-info/10"
                          aria-label={"Edit rule #{rule.id}"}
                          title="Edit rule"
                        >
                          <.icon name="hero-pencil-square" class="size-4" />
                        </button>
                      <% else %>
                        <span class="inline-flex h-6 w-6"></span>
                      <% end %>
                      <button
                        type="button"
                        phx-click="confirm_delete_rule"
                        phx-value-id={rule.id}
                        class="btn btn-ghost btn-xs px-1 text-error hover:bg-error/10"
                        aria-label={"Delete rule #{rule.id}"}
                        title="Delete rule"
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <%= if Enum.empty?(@rules) do %>
            <div class="p-6 text-center text-base-content/50">No rules defined yet.</div>
          <% end %>
        </div>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="rule-modal"
        show
        on_cancel={JS.push("request_close_rule_modal")}
        close_on_cancel={false}
      >
        <.header>
          {modal_title(@live_action)}
          <:subtitle>Configure schema-driven conditions for alert generation.</:subtitle>
        </.header>

        <.simple_form
          id="alert-rule-form"
          for={@form}
          as={:alert_rule}
          phx-change="validate_rule"
          phx-submit="save_rule"
          phx-hook="AlertRuleBuilderKeyboard"
        >
          <div class="grid grid-cols-1 gap-4 mb-6">
            <div class="ui-fieldset">
              <.input
                field={@form[:name]}
                id="alert-rule-name"
                type="text"
                label="Rule Name"
                placeholder="e.g. High temperature"
                disabled={@live_action == :edit}
              />
              <input
                :if={@live_action == :edit}
                type="hidden"
                name="form[name]"
                value={@form[:name].value || ""}
              />
            </div>
            <div class="ui-fieldset">
              <label for="alert-schema-id" class="ui-label-inline">
                <span>Schema Product</span>
                <span
                  class="tooltip tooltip-right cursor-help"
                  data-tip="Select the schema context used for condition validation."
                  aria-label="Schema product help"
                >
                  <.icon name="hero-question-mark-circle" class="size-4 text-base-content/70" />
                </span>
              </label>
              <select
                id="alert-schema-id"
                name="schema_id"
                value={@selected_schema_id || ""}
                class="ui-select"
                disabled={!is_nil(@rule_edit_blocked_reason)}
              >
                <option value="">Select product/schema</option>
                <%= for {label, value} <- schema_id_options(@schema_refs) do %>
                  <option value={value} selected={@selected_schema_id == value}>{label}</option>
                <% end %>
              </select>
            </div>
            <div class="ui-fieldset">
              <label for="alert-schema-version" class="ui-label">Schema Version</label>
              <select
                id="alert-schema-version"
                name="schema_version"
                value={@selected_schema_version || ""}
                class="ui-select"
                disabled={!is_nil(@rule_edit_blocked_reason)}
              >
                <option value="">Select version</option>
                <%= for {label, value} <- schema_version_options(@schema_refs, @selected_schema_id) do %>
                  <option value={value} selected={@selected_schema_version == value}>{label}</option>
                <% end %>
              </select>
            </div>
            <p class="ui-help-text">
              Rules evaluate telemetry fields from the selected schema version.
            </p>
          </div>

          <%= if @no_schema_fields_message do %>
            <p class="mt-2 text-sm text-warning">{@no_schema_fields_message}</p>
          <% end %>

          <div class="grid grid-cols-1 gap-4 mt-2 mb-6">
            <div class="bg-base-200 p-3 rounded border border-base-300 grid grid-cols-1 md:grid-cols-3 gap-4 items-start">
              <div>
                <.input
                  field={@form[:condition_field]}
                  id="alert-condition-field"
                  type="select"
                  label="Schema Field"
                  options={@schema_options}
                  prompt="Select schema field"
                  disabled={!is_nil(@rule_edit_blocked_reason)}
                />
              </div>
              <div>
                <.input
                  field={@form[:operator]}
                  id="alert-operator"
                  type="select"
                  label="Operator"
                  options={operator_options(@form[:condition_field].value, @schema_option_types)}
                  disabled={!is_nil(@rule_edit_blocked_reason)}
                />
              </div>
              <div>
                <.input
                  field={@form[:threshold_value]}
                  type="text"
                  id="alert-threshold-value"
                  label="Threshold"
                  placeholder={threshold_placeholder(@form[:condition_field].value, @schema_option_types)}
                  disabled={!is_nil(@rule_edit_blocked_reason)}
                />
              </div>
            </div>

            <div>
              <p class="ui-help-text">
                Tip: use <kbd>Ctrl</kbd>/<kbd>Cmd</kbd> + <kbd>Enter</kbd> to save.
              </p>
            </div>

            <div>
              <%= if @rule_edit_blocked_reason do %>
                <p class="text-sm text-error mt-8" role="alert">{@rule_edit_blocked_reason}</p>
              <% end %>
              <%= if @schema_issue do %>
                <p class="text-sm text-error mt-8" role="alert">{@schema_issue}</p>
              <% end %>
            </div>
          </div>

          <div class="flex justify-end pt-4 border-t border-base-300 gap-2">
            <.button
              id="alert-rule-save"
              disabled={
                !rule_save_enabled?(%{
                  selected_schema_id: @selected_schema_id,
                  schema_options: @schema_options,
                  schema_issue: @schema_issue,
                  no_schema_fields_message: @no_schema_fields_message,
                  condition_field: @form[:condition_field].value,
                  operator: @form[:operator].value,
                  threshold_value: @form[:threshold_value].value,
                  live_action: @live_action,
                  rule_editing: @rule_editing,
                  rule_edit_blocked_reason: @rule_edit_blocked_reason
                })
              }
              phx-disable-with="Saving..."
            >
              {save_button_label(@live_action)}
            </.button>
          </div>
        </.simple_form>
      </.modal>

      <.modal :if={@rule_to_delete} id="delete-rule-modal" show on_cancel={JS.push("cancel_delete_rule")}>
        <div class="space-y-4">
          <h3 class="text-lg font-semibold">Delete Rule</h3>
          <p>
            Are you sure you want to delete this rule for <span class="font-bold">{@rule_to_delete.product_name}</span>?
            This action cannot be undone.
          </p>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_delete_rule">Cancel</button>
            <button type="button" class="btn btn-error btn-sm" phx-click="delete_rule">Delete</button>
          </div>
        </div>
      </.modal>

      <.modal
        :if={@show_discard_confirm}
        id="discard-rule-modal"
        show
        on_cancel={JS.push("cancel_discard_rule_changes")}
      >
        <.header>
          Discard Changes?
          <:subtitle>You have unsaved edits. Do you want to discard them?</:subtitle>
        </.header>
        <div class="flex items-center justify-end gap-3 pt-2">
          <.button type="button" variant="outline" phx-click="cancel_discard_rule_changes">Keep Editing</.button>
          <.button type="button" phx-click="confirm_discard_rule_changes">Discard</.button>
        </div>
      </.modal>
    </div>
    """
  end

  defp apply_action(socket, :new, _params) do
    schema_refs = SchemaOptions.list_schema_references()
    selected_schema_id = schema_refs |> List.first() |> then(&if(&1, do: &1.schema_id, else: nil))
    selected_schema_version = first_schema_version(schema_refs, selected_schema_id)

    {schema_options, schema_option_types} =
      fetch_schema_option_metadata(selected_schema_id, selected_schema_version)

    form =
      AlertRule
      |> AshPhoenix.Form.for_create(:create,
        domain: Domain,
        params: %{"name" => "", "product_name" => selected_schema_id || ""}
      )
      |> to_form()

    initial_draft =
      draft_state_from(selected_schema_id, selected_schema_version, %{
        "name" => "",
        "product_name" => selected_schema_id || "",
        "condition_field" => "",
        "operator" => "",
        "threshold_value" => ""
      })

    socket
    |> assign(:page_title, "Add Rule")
    |> assign(:form, form)
    |> assign(:schema_refs, schema_refs)
    |> assign(:selected_schema_id, selected_schema_id)
    |> assign(:selected_schema_version, selected_schema_version)
    |> assign(:schema_options, schema_options)
    |> assign(:schema_option_types, schema_option_types)
    |> assign(:schema_issue, nil)
    |> assign(:rule_dirty?, false)
    |> assign(:rule_initial_draft, initial_draft)
    |> assign(:rule_editing, nil)
    |> assign(:rule_edit_blocked_reason, nil)
    |> assign(:rule_to_delete, nil)
    |> assign(:show_discard_confirm, false)
    |> assign(
      :no_schema_fields_message,
      no_schema_fields_message(selected_schema_id, schema_options)
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    rule =
      id
      |> parse_id()
      |> Domain.get_rule!()

    schema_refs = SchemaOptions.list_schema_references()
    selected_schema_id = rule.product_name

    selected_schema_version =
      schema_version_for_existing_field(schema_refs, selected_schema_id, rule.condition_field)

    {base_schema_options, schema_option_types} =
      fetch_schema_option_metadata(selected_schema_id, selected_schema_version)

    field_valid_for_schema? =
      Enum.any?(base_schema_options, fn {_label, key} -> key == rule.condition_field end)

    rule_edit_blocked_reason =
      invalid_rule_edit_reason(
        field_valid_for_schema?,
        selected_schema_id,
        selected_schema_version
      )

    schema_options = ensure_field_option(base_schema_options, rule.condition_field)

    form =
      rule
      |> AshPhoenix.Form.for_update(:update, domain: Domain)
      |> to_form()

    initial_draft =
      draft_state_from(selected_schema_id, selected_schema_version, %{
        "product_name" => rule.product_name,
        "name" => rule.name,
        "condition_field" => rule.condition_field,
        "operator" => to_string(rule.operator),
        "threshold_value" => rule.threshold_value
      })

    socket
    |> assign(:page_title, "Edit Rule")
    |> assign(:form, form)
    |> assign(:schema_refs, schema_refs)
    |> assign(:selected_schema_id, selected_schema_id)
    |> assign(:selected_schema_version, selected_schema_version)
    |> assign(:schema_options, schema_options)
    |> assign(:schema_option_types, schema_option_types)
    |> assign(:schema_issue, nil)
    |> assign(:rule_dirty?, false)
    |> assign(:rule_initial_draft, initial_draft)
    |> assign(:rule_editing, rule)
    |> assign(:rule_edit_blocked_reason, rule_edit_blocked_reason)
    |> assign(:rule_to_delete, nil)
    |> assign(:show_discard_confirm, false)
    |> assign(
      :no_schema_fields_message,
      no_schema_fields_message(selected_schema_id, schema_options)
    )
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Alerts")
    |> assign_rules(Domain.list_rules!())
    |> assign(:form, nil)
    |> assign(:schema_refs, [])
    |> assign(:selected_schema_id, nil)
    |> assign(:selected_schema_version, nil)
    |> assign(:schema_options, [])
    |> assign(:schema_option_types, %{})
    |> assign(:schema_issue, nil)
    |> assign(:rule_dirty?, false)
    |> assign(:rule_initial_draft, %{})
    |> assign(:rule_editing, nil)
    |> assign(:rule_edit_blocked_reason, nil)
    |> assign(:rule_to_delete, nil)
    |> assign(:show_discard_confirm, false)
    |> assign(:no_schema_fields_message, nil)
  end

  defp normalize_rule_payload(params, socket) do
    rule_params = extract_rule_params(params)

    submitted_schema_id =
      blank_to_nil(Map.get(params, "schema_id", socket.assigns.selected_schema_id))

    schema_id =
      cond do
        submitted_schema_id not in [nil, ""] -> submitted_schema_id
        present?(Map.get(rule_params, "product_name", "")) -> Map.get(rule_params, "product_name")
        true -> socket.assigns.selected_schema_id
      end

    schema_version =
      blank_to_nil(Map.get(params, "schema_version", socket.assigns.selected_schema_version)) ||
        first_schema_version(SchemaOptions.list_schema_references(), schema_id)

    rule_params =
      rule_params
      |> Map.put("product_name", schema_id || "")
      |> maybe_restore_rule_name(socket)
      |> maybe_restore_condition_field(socket)
      |> Map.put("operator", normalize_operator(Map.get(rule_params, "operator")))

    {schema_id, schema_version, rule_params}
  end

  defp normalize_operator(nil), do: "="
  defp normalize_operator(""), do: "="
  defp normalize_operator(value), do: value

  defp maybe_restore_rule_name(rule_params, %{assigns: %{live_action: :edit, rule_editing: rule}}) do
    Map.put(rule_params, "name", rule.name || "")
  end

  defp maybe_restore_rule_name(rule_params, _socket), do: rule_params

  defp maybe_restore_condition_field(rule_params, %{
         assigns: %{live_action: :edit, rule_editing: rule}
       }) do
    case Map.get(rule_params, "condition_field") do
      value ->
        if present?(value) do
          rule_params
        else
          Map.put(rule_params, "condition_field", rule.condition_field || "")
        end
    end
  end

  defp maybe_restore_condition_field(rule_params, _socket), do: rule_params

  defp schema_id_options(refs) do
    refs
    |> Enum.map(& &1.schema_id)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&{&1, &1})
  end

  defp schema_version_options(refs, schema_id) do
    refs
    |> Enum.filter(&(&1.schema_id == schema_id))
    |> Enum.map(& &1.schema_version)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&{&1, &1})
  end

  defp first_schema_version(refs, schema_id) do
    refs
    |> Enum.find(&(&1.schema_id == schema_id))
    |> then(&if(&1, do: &1.schema_version, else: nil))
  end

  defp schema_version_for_existing_field(schema_refs, schema_id, condition_field) do
    candidate_versions =
      schema_refs
      |> Enum.filter(&(&1.schema_id == schema_id))
      |> Enum.map(& &1.schema_version)
      |> Enum.uniq()

    Enum.find(candidate_versions, &schema_options_include_field?(&1, schema_id, condition_field)) ||
      first_schema_version(schema_refs, schema_id)
  end

  defp schema_options_include_field?(schema_version, schema_id, condition_field) do
    {options, _types} = fetch_schema_option_metadata(schema_id, schema_version)
    Enum.any?(options, fn {_label, key} -> key == condition_field end)
  end

  defp ensure_field_option(options, condition_field) do
    if present?(condition_field) and
         Enum.any?(options, fn {_label, key} -> key == condition_field end) do
      options
    else
      if present?(condition_field) do
        options ++ [{humanize_field_name(condition_field), condition_field}]
      else
        options
      end
    end
  end

  defp fetch_schema_option_metadata(nil, _), do: {[], %{}}
  defp fetch_schema_option_metadata(_, nil), do: {[], %{}}

  defp fetch_schema_option_metadata(schema_id, schema_version) do
    case SchemaOptions.options_for(schema_id, schema_version, :alert) do
      {:ok, %{options: options}} ->
        option_pairs = Enum.map(options, &{&1.label, &1.key})
        option_types = Map.new(options, &{&1.key, &1.value_type})
        {option_pairs, option_types}

      _ ->
        {[], %{}}
    end
  end

  defp no_schema_fields_message(nil, _), do: nil

  defp no_schema_fields_message(_, options) when options == [],
    do: "No schema fields are available for this schema/version."

  defp no_schema_fields_message(_, _), do: nil

  defp maybe_clear_invalid_condition_field(params, condition_field, valid_field?) do
    if condition_field != "" and not valid_field? do
      Map.put(params, "condition_field", "")
    else
      params
    end
  end

  defp schema_issue("", _, issues), do: first_issue_message(issues)

  defp schema_issue(_condition_field, false, _issues),
    do: "Selected field is no longer valid for the active schema."

  defp schema_issue(_condition_field, true, issues), do: first_issue_message(issues)

  defp first_issue_message([%{message: message} | _]) when is_binary(message), do: message
  defp first_issue_message(_), do: nil

  defp save_rule_result(socket, context) do
    schema_id = context.schema_id
    schema_options = context.schema_options
    schema_option_types = context.schema_option_types
    no_schema_fields_message = context.no_schema_fields_message
    validation = context.validation
    issues = context.issues
    rule_params = context.rule_params
    rule_edit_blocked_reason = Map.get(context, :rule_edit_blocked_reason)

    cond do
      present?(rule_edit_blocked_reason) ->
        record_invalid_attempt()

        {:noreply,
         socket
         |> assign(:schema_issue, nil)
         |> put_flash(:error, rule_edit_blocked_reason)}

      schema_id in [nil, ""] ->
        {:noreply, put_flash(socket, :error, "Select a schema product before saving.")}

      schema_options == [] ->
        record_invalid_attempt()

        {:noreply,
         socket
         |> assign(:no_schema_fields_message, no_schema_fields_message)
         |> put_flash(:error, "This schema has no available fields for rules.")}

      not validation.valid ->
        record_invalid_attempt()

        {:noreply,
         socket
         |> assign(:schema_issue, "Selected field is invalid for the active schema.")
         |> put_flash(:error, "Please select a valid schema field before saving.")}

      issues != [] ->
        record_invalid_attempt()

        {:noreply,
         socket
         |> assign(:schema_option_types, schema_option_types)
         |> assign(:schema_issue, first_issue_message(issues))
         |> put_flash(:error, first_issue_message(issues))}

      true ->
        persist_rule_submit(
          socket,
          rule_params,
          context.schema_id,
          context.schema_version,
          schema_options,
          schema_option_types,
          no_schema_fields_message
        )
    end
  end

  defp persist_rule_submit(
         socket,
         rule_params,
         schema_id,
         schema_version,
         schema_options,
         schema_option_types,
         no_schema_fields_message
       ) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: rule_params) do
      {:ok, _rule} ->
        :telemetry.execute(
          [:nixstasis, :builder, :first_attempt_success],
          %{count: 1},
          %{builder: "alert"}
        )

        generation = socket.assigns.success_flash_generation + 1
        Process.send_after(self(), {:clear_flash, :info, generation}, @success_flash_timeout_ms)

        {:noreply,
         socket
         |> assign(:success_flash_generation, generation)
         |> put_flash(:info, success_message(socket.assigns.live_action))
         |> push_patch(to: ~p"/alerts?tab=rules")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> assign(:selected_schema_id, schema_id)
         |> assign(:selected_schema_version, schema_version)
         |> assign(:schema_options, schema_options)
         |> assign(:schema_option_types, schema_option_types)
         |> assign(:schema_issue, nil)
         |> assign(:no_schema_fields_message, no_schema_fields_message)
         |> put_flash(:error, "Unable to save rule. Correct the highlighted fields.")}
    end
  end

  defp record_invalid_attempt do
    :telemetry.execute(
      [:nixstasis, :builder, :invalid_save_attempt],
      %{count: 1},
      %{builder: "alert"}
    )
  end

  defp normalize_operator_for_field(rule_params, schema_option_types) do
    field = Map.get(rule_params, "condition_field", "")
    field_type = Map.get(schema_option_types, field, "unknown")
    operator = normalize_string_operator(Map.get(rule_params, "operator", "="), field_type)

    if String.trim(operator) == "" do
      Map.put(rule_params, "operator", default_operator_for_type(field_type))
    else
      Map.put(rule_params, "operator", operator)
    end
  end

  defp default_operator_for_type("number"), do: ">"
  defp default_operator_for_type(_), do: "is"

  defp operator_options(condition_field, schema_option_types) do
    field_type = Map.get(schema_option_types, condition_field || "", "unknown")
    AlertRule.operator_options_for_type(field_type)
  end

  defp threshold_placeholder(condition_field, schema_option_types) do
    case Map.get(schema_option_types, condition_field || "", "unknown") do
      "number" -> "e.g. 50"
      _ -> "e.g. ok42"
    end
  end

  defp normalize_string_operator("=", "string"), do: "is"
  defp normalize_string_operator("!=", "string"), do: "is not"
  defp normalize_string_operator(operator, _field_type), do: operator

  defp extract_rule_params(params) when is_map(params) do
    form_params = Map.get(params, "form") || %{}
    alert_rule_params = Map.get(params, "alert_rule") || %{}
    Map.merge(form_params, alert_rule_params)
  end

  defp draft_state_from(schema_id, schema_version, rule_params) do
    %{
      "schema_id" => schema_id || "",
      "schema_version" => schema_version || "",
      "name" => Map.get(rule_params, "name", ""),
      "product_name" => Map.get(rule_params, "product_name", ""),
      "condition_field" => Map.get(rule_params, "condition_field", ""),
      "operator" => Map.get(rule_params, "operator", "="),
      "threshold_value" => Map.get(rule_params, "threshold_value", "")
    }
  end

  defp dirty_draft?(initial, current), do: initial != current

  defp modal_title(:edit), do: "Edit Rule"
  defp modal_title(_), do: "Add Rule"

  defp save_button_label(:edit), do: "Save Changes"
  defp save_button_label(_), do: "Create Rule"

  defp success_message(:edit), do: "Rule updated successfully"
  defp success_message(_), do: "Rule created successfully"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> raise ArgumentError, "invalid id"
    end
  end

  defp assign_rules(socket, rules) do
    schema_refs = SchemaOptions.list_schema_references()

    decorated_rules =
      Enum.map(rules, fn rule ->
        edit_disabled_reason = rule_edit_disabled_reason(rule, schema_refs)

        %{
          id: rule.id,
          name: rule.name,
          product_name: rule.product_name,
          condition_field: rule.condition_field,
          operator: to_string(rule.operator),
          threshold_value: rule.threshold_value,
          updated_at: rule.updated_at,
          edit_disabled_reason: edit_disabled_reason,
          rule: rule
        }
      end)

    socket
    |> assign(:all_rules, decorated_rules)
    |> apply_rule_filters()
  end

  defp apply_rule_filters(socket) do
    query = socket.assigns.rule_filters["query"] || ""
    filtered = filter_rules(socket.assigns.all_rules || [], query)
    sorted = sort_rules(filtered, socket.assigns.rule_sort_by, socket.assigns.rule_sort_dir)
    assign(socket, :rules, sorted)
  end

  defp filter_rules(rules, ""), do: rules

  defp filter_rules(rules, query) do
    needle = String.downcase(String.trim(query))

    Enum.filter(rules, fn rule ->
      haystack =
        Enum.map_join(
          [
            rule.product_name,
            rule.name,
            rule.condition_field,
            rule.operator,
            rule.threshold_value
          ],
          " ",
          &String.downcase(to_string(&1))
        )

      String.contains?(haystack, needle)
    end)
  end

  defp sort_rules(rules, by, dir) do
    sorter =
      case by do
        "condition_field" -> & &1.condition_field
        "operator" -> & &1.operator
        "updated_at" -> & &1.updated_at
        "name" -> & &1.name
        _ -> & &1.product_name
      end

    Enum.sort_by(rules, sorter, sort_direction(dir))
  end

  defp sort_direction("desc"), do: :desc
  defp sort_direction(_), do: :asc

  defp sort_indicator(current_by, current_dir, expected_by) do
    if current_by == expected_by do
      if current_dir == "asc", do: "↑", else: "↓"
    else
      ""
    end
  end

  defp normalize_tab("rules"), do: "rules"
  defp normalize_tab(_), do: "active"

  defp humanize_field_name(key) when is_binary(key) do
    key
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize_field_name(_), do: "Schema Field"

  defp invalid_rule_edit_reason(true, _schema_id, _schema_version), do: nil

  defp invalid_rule_edit_reason(false, schema_id, schema_version) do
    schema_label =
      [schema_id, schema_version]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" / ")

    if schema_label == "" do
      "This rule references a schema field that is no longer valid. Editing is disabled."
    else
      "This rule references a schema field that is no longer valid for #{schema_label}. Editing is disabled."
    end
  end

  defp rule_edit_disabled_reason(rule, schema_refs) do
    selected_schema_id = rule.product_name

    selected_schema_version =
      schema_version_for_existing_field(schema_refs, selected_schema_id, rule.condition_field)

    {schema_options, _schema_option_types} =
      fetch_schema_option_metadata(selected_schema_id, selected_schema_version)

    field_valid_for_schema? =
      Enum.any?(schema_options, fn {_label, key} -> key == rule.condition_field end)

    invalid_rule_edit_reason(field_valid_for_schema?, selected_schema_id, selected_schema_version)
  end

  defp rule_save_enabled?(assigns) do
    if base_rule_save_valid?(assigns) do
      case assigns.live_action do
        :edit ->
          edit_rule_values_changed?(
            assigns.rule_editing,
            assigns.condition_field,
            assigns.operator,
            assigns.threshold_value
          )

        _ ->
          true
      end
    else
      false
    end
  end

  defp base_rule_save_valid?(assigns) do
    assigns.selected_schema_id not in [nil, ""] and
      is_list(assigns.schema_options) and assigns.schema_options != [] and
      is_nil(assigns.schema_issue) and
      is_nil(assigns.rule_edit_blocked_reason) and
      is_nil(assigns.no_schema_fields_message) and
      present?(assigns.condition_field) and
      present?(assigns.operator) and
      present?(assigns.threshold_value)
  end

  defp edit_rule_values_changed?(nil, _condition_field, _operator, _threshold_value), do: false

  defp edit_rule_values_changed?(rule, condition_field, operator, threshold_value) do
    condition_changed? =
      normalize_compare_value(condition_field) != normalize_compare_value(rule.condition_field)

    operator_changed? =
      normalize_compare_value(operator) != normalize_compare_value(rule.operator)

    threshold_changed? =
      not values_equivalent?(
        normalize_compare_value(threshold_value),
        normalize_compare_value(rule.threshold_value)
      )

    condition_changed? or operator_changed? or threshold_changed?
  end

  defp normalize_compare_value(value), do: value |> to_string() |> String.trim()

  defp values_equivalent?(left, right) when left == right, do: true

  defp values_equivalent?(left, right) do
    case {Float.parse(left), Float.parse(right)} do
      {{left_num, ""}, {right_num, ""}} -> left_num == right_num
      _ -> false
    end
  end
end
