defmodule NixstasisWeb.AlertLive.Index do
  use NixstasisWeb, :live_view

  require Ash.Query

  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.Alert
  alias Nixstasis.Monitoring.AlertRule
  alias Nixstasis.SchemaOptions

  def mount(_params, _session, socket) do
    alerts =
      Alert
      |> Ash.Query.sort(triggered_at: :desc)
      |> Ash.Query.load(:device)
      |> Ash.read!(domain: Domain)

    {:ok, stream(socket, :alerts, alerts)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    schema_refs = SchemaOptions.list_schema_references()
    selected_schema_id = schema_refs |> List.first() |> then(&if(&1, do: &1.schema_id, else: nil))
    selected_schema_version = first_schema_version(schema_refs, selected_schema_id)
    schema_options = fetch_schema_options(selected_schema_id, selected_schema_version)

    form =
      AlertRule
      |> AshPhoenix.Form.for_create(:create, domain: Domain, params: %{"product_name" => selected_schema_id || ""})
      |> to_form()

    socket
    |> assign(:page_title, "Add Rule")
    |> assign(:form, form)
    |> assign(:schema_refs, schema_refs)
    |> assign(:selected_schema_id, selected_schema_id)
    |> assign(:selected_schema_version, selected_schema_version)
    |> assign(:schema_options, schema_options)
    |> assign(:schema_issue, nil)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Alerts")
    |> assign(:form, nil)
    |> assign(:schema_refs, [])
    |> assign(:selected_schema_id, nil)
    |> assign(:selected_schema_version, nil)
    |> assign(:schema_options, [])
    |> assign(:schema_issue, nil)
  end

  def handle_event("save_rule", params, socket) do
    rule_params = extract_rule_params(params)
    schema_id = socket.assigns.selected_schema_id
    schema_version = socket.assigns.selected_schema_version

    validation =
      SchemaOptions.validate_selections(:alert, schema_id || "", schema_version || "", [
        %{"slot_id" => "condition_field", "selected_key" => rule_params["condition_field"]}
      ])

    rule_params = Map.put(rule_params, "product_name", schema_id || rule_params["product_name"] || "")

    case validation.valid do
      false ->
        :telemetry.execute(
          [:nixstasis, :builder, :invalid_save_attempt],
          %{count: 1},
          %{builder: "alert"}
        )

        {:noreply,
         socket
         |> assign(:schema_issue, "Selected field is invalid for the active schema.")
         |> put_flash(:error, "Please select a valid schema field before saving.")}

      true ->
        case AshPhoenix.Form.submit(socket.assigns.form, params: rule_params) do
          {:ok, _rule} ->
            :telemetry.execute(
              [:nixstasis, :builder, :first_attempt_success],
              %{count: 1},
              %{builder: "alert"}
            )

            {:noreply,
             socket
             |> put_flash(:info, "Rule created successfully")
             |> push_patch(to: ~p"/alerts")}

          {:error, form} ->
            {:noreply, assign(socket, :form, form)}
        end
    end
  end

  def handle_event("validate_rule", params, socket) do
    rule_params = extract_rule_params(params)
    condition_field = rule_params["condition_field"] || ""
    valid_field? = Enum.any?(socket.assigns.schema_options, fn {_label, value} -> value == condition_field end)

    rule_params =
      if condition_field != "" and not valid_field? do
        Map.put(rule_params, "condition_field", "")
      else
        rule_params
      end
      |> Map.put("product_name", socket.assigns.selected_schema_id || "")

    form = AshPhoenix.Form.validate(socket.assigns.form, rule_params)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:schema_issue, if(valid_field?, do: nil, else: maybe_field_issue(condition_field)))}
  end

  def handle_event("set_alert_schema_id", %{"schema_id" => schema_id}, socket) do
    selected_schema_id = blank_to_nil(schema_id) || socket.assigns.selected_schema_id
    selected_schema_version = first_schema_version(socket.assigns.schema_refs, selected_schema_id)
    schema_options = fetch_schema_options(selected_schema_id, selected_schema_version)

    current_field = socket.assigns.form[:condition_field].value || ""
    valid_field? = Enum.any?(schema_options, fn {_label, value} -> value == current_field end)

    params = %{
      "product_name" => selected_schema_id || "",
      "condition_field" => if(valid_field?, do: current_field, else: "")
    }

    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:selected_schema_id, selected_schema_id)
     |> assign(:selected_schema_version, selected_schema_version)
     |> assign(:schema_options, schema_options)
     |> assign(:schema_issue, if(valid_field?, do: nil, else: maybe_field_issue(current_field)))}
  end

  def handle_event("set_alert_schema_version", %{"schema_version" => version}, socket) do
    schema_options = fetch_schema_options(socket.assigns.selected_schema_id, version)

    current_field = socket.assigns.form[:condition_field].value || ""
    valid_field? = Enum.any?(schema_options, fn {_label, value} -> value == current_field end)

    params = %{
      "product_name" => socket.assigns.selected_schema_id || "",
      "condition_field" => if(valid_field?, do: current_field, else: "")
    }

    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:selected_schema_version, version)
     |> assign(:schema_options, schema_options)
     |> assign(:schema_issue, if(valid_field?, do: nil, else: maybe_field_issue(current_field)))}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl">
      <.header>
        Alerts
        <:subtitle>System notifications and device alerts</:subtitle>
        <:actions>
          <.link patch={~p"/alerts/new"}>
            <.button>Add Rule</.button>
          </.link>
        </:actions>
      </.header>

      <.table
        id="alerts"
        rows={@streams.alerts}
      >
        <:col :let={{_id, alert}} label="Type">
          <span class={["badge", alert.type == :offline && "badge-error"]}>{alert.type}</span>
        </:col>
        <:col :let={{_id, alert}} label="Device">
          {if alert.device, do: alert.device.mac_address, else: "-"}
        </:col>
        <:col :let={{_id, alert}} label="Message">{alert.message}</:col>
        <:col :let={{_id, alert}} label="Time">{alert.triggered_at}</:col>
        <:col :let={{_id, alert}} label="Status">{alert.status}</:col>
      </.table>

      <.modal :if={@live_action == :new} id="rule-modal" show on_cancel={JS.patch(~p"/alerts")}>
        <.header>
          Add Rule
          <:subtitle>Create a new automation rule.</:subtitle>
        </.header>
        <.simple_form
          for={@form}
          as={:alert_rule}
          phx-submit="save_rule"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.schema_select
              id="alert-schema-id"
              name="schema_id"
              label="Schema Product"
              value={@selected_schema_id}
              options={schema_id_options(@schema_refs)}
              prompt="Select product/schema"
              phx-change="set_alert_schema_id"
            />
            <.schema_select
              id="alert-schema-version"
              name="schema_version"
              label="Schema Version"
              value={@selected_schema_version}
              options={schema_version_options(@schema_refs, @selected_schema_id)}
              prompt="Select schema version"
              phx-change="set_alert_schema_version"
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input
              field={@form[:condition_field]}
              type="select"
              label="Schema Field"
              options={@schema_options}
              prompt="Select schema field"
            />
            <%= if @schema_issue do %>
              <p class="text-sm text-error mt-2 md:mt-8">{@schema_issue}</p>
            <% end %>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input
              field={@form[:operator]}
              type="select"
              label="Operator"
              options={[">", "<", "=", "!=", ">=", "<="]}
            />
            <.input field={@form[:threshold_value]} label="Threshold" placeholder="e.g. 50" />
          </div>

          <:actions>
            <.button phx-disable-with="Saving...">Create Rule</.button>
          </:actions>
        </.simple_form>
      </.modal>
    </div>
    """
  end

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
    |> Enum.map(&{&1.schema_version, &1.schema_version})
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp first_schema_version(refs, schema_id) do
    refs
    |> Enum.find(&(&1.schema_id == schema_id))
    |> then(&if(&1, do: &1.schema_version, else: nil))
  end

  defp fetch_schema_options(nil, _), do: []
  defp fetch_schema_options(_, nil), do: []

  defp fetch_schema_options(schema_id, schema_version) do
    case SchemaOptions.options_for(schema_id, schema_version, :alert) do
      {:ok, %{options: options}} ->
        Enum.map(options, &{&1.label, &1.key})

      _ ->
        []
    end
  end

  defp maybe_field_issue(""), do: nil
  defp maybe_field_issue(_), do: "Selected field is no longer valid for the active schema."

  defp extract_rule_params(params) when is_map(params) do
    Map.get(params, "alert_rule") || Map.get(params, "form") || %{}
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
