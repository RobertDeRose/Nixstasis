defmodule NixstasisWeb.AlertLive.Rules do
  use NixstasisWeb, :live_view

  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.AlertRule

  def mount(_params, _session, socket) do
    form =
      AlertRule
      |> AshPhoenix.Form.for_create(:create, domain: Domain)
      |> to_form()

    {:ok,
     socket
     |> assign(:rules, Domain.list_rules!())
     |> assign(:form, form)}
  end

  def handle_event("save", %{"alert_rule" => rule_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: rule_params) do
      {:ok, _rule} ->
        form =
          AlertRule
          |> AshPhoenix.Form.for_create(:create, domain: Domain)
          |> to_form()

        {:noreply,
         socket
         |> put_flash(:info, "Rule created successfully")
         |> assign(:rules, Domain.list_rules!())
         |> assign(:form, form)}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("validate", %{"alert_rule" => rule_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, rule_params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    rule = Domain.get_rule!(id)
    {:ok, _} = Domain.destroy_rule(rule)

    {:noreply,
     socket
     |> put_flash(:info, "Rule deleted")
     |> assign(:rules, Domain.list_rules!())}
  end

  def render(assigns) do
    ~H"""
    <div class="ui-page-shell">
      <.header>
        Alert Rules
        <:subtitle>Manage automation rules for generating alerts.</:subtitle>
        <:actions>
          <.link navigate={~p"/alerts"}>
            <.button variant="outline">&larr; Back to Alerts</.button>
          </.link>
        </:actions>
      </.header>

      <div class="ui-card-panel mb-8">
        <div class="card-body">
          <h2 class="card-title">Create New Rule</h2>
          <.simple_form for={@form} as={:alert_rule} phx-change="validate" phx-submit="save">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <.input
                field={@form[:product_name]}
                label="Product Name"
                placeholder="e.g. thermostat-v1"
              />
              <.input
                field={@form[:condition_field]}
                label="JSON Path"
                placeholder="e.g. temp or sensors.temp"
              />
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
        </div>
      </div>

      <div class="ui-card-panel">
        <div class="card-body p-0">
          <.table id="rules" rows={@rules}>
            <:col :let={rule} label="Product Name">{rule.product_name}</:col>
            <:col :let={rule} label="Condition">
              <code class="bg-base-200 px-2 py-1 rounded">{rule.condition_field}</code>
              <span class="mx-2 font-bold">{rule.operator}</span>
              <span class="text-base-content">{rule.threshold_value}</span>
            </:col>
            <:action :let={rule}>
              <.link
                phx-click="delete"
                phx-value-id={rule.id}
                data-confirm="Are you sure?"
                class="text-error hover:text-error/80"
              >
                Delete
              </.link>
            </:action>
          </.table>

          <%= if Enum.empty?(@rules) do %>
            <div class="p-6 text-center text-base-content/50">No rules defined yet.</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
