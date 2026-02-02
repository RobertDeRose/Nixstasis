defmodule NixstasisWeb.AlertLive.Rules do
  use NixstasisWeb, :live_view
  alias Nixstasis.Monitoring
  alias Nixstasis.Monitoring.AlertRule

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:rules, Monitoring.list_rules())
     |> assign(:form, to_form(Monitoring.AlertRule.changeset(%Monitoring.AlertRule{}, %{})))}
  end

  def handle_event("save", %{"alert_rule" => rule_params}, socket) do
    case Monitoring.create_rule(rule_params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rule created successfully")
         |> assign(:rules, Monitoring.list_rules())
         |> assign(:form, to_form(Monitoring.AlertRule.changeset(%Monitoring.AlertRule{}, %{})))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("validate", %{"alert_rule" => rule_params}, socket) do
    changeset =
      %AlertRule{}
      |> AlertRule.changeset(rule_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    rule = Monitoring.get_rule!(id)
    {:ok, _} = Monitoring.delete_rule(rule)

    {:noreply,
     socket
     |> put_flash(:info, "Rule deleted")
     |> assign(:rules, Monitoring.list_rules())}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <div class="mb-8 flex items-center justify-between">
        <h1 class="text-2xl font-bold">Alert Rules</h1>
        <.link navigate={~p"/alerts"} class="text-blue-600 hover:underline">
          &larr; Back to Alerts
        </.link>
      </div>

      <div class="bg-white p-6 rounded-lg shadow mb-8">
        <h2 class="text-lg font-semibold mb-4">Create New Rule</h2>
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input field={@form[:product_key]} label="Product Key" placeholder="e.g. thermostat-v1" />
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

          <div class="flex justify-end">
            <.button phx-disable-with="Saving...">Create Rule</.button>
          </div>
        </.form>
      </div>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Product Key
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Condition
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for rule <- @rules do %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  {rule.product_key}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <code class="bg-gray-100 px-2 py-1 rounded">{rule.condition_field}</code>
                  <span class="mx-2 font-bold">{rule.operator}</span>
                  <span class="text-gray-900">{rule.threshold_value}</span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <button
                    phx-click="delete"
                    phx-value-id={rule.id}
                    data-confirm="Are you sure?"
                    class="text-red-600 hover:text-red-900"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <%= if Enum.empty?(@rules) do %>
          <div class="p-6 text-center text-gray-500">No rules defined yet.</div>
        <% end %>
      </div>
    </div>
    """
  end
end
