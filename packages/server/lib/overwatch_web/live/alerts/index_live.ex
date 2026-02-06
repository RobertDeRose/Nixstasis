defmodule NixstasisWeb.AlertLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.Repo
  import Ecto.Query
  alias Nixstasis.Monitoring
  alias Nixstasis.Monitoring.Alert
  alias Nixstasis.Monitoring.AlertRule

  def mount(_params, _session, socket) do
    alerts =
      from(a in Alert, order_by: [desc: a.triggered_at], preload: [:device])
      |> Repo.all()

    {:ok, stream(socket, :alerts, alerts)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Add Rule")
    |> assign(:form, to_form(Monitoring.AlertRule.changeset(%Monitoring.AlertRule{}, %{})))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Alerts")
    |> assign(:form, nil)
  end

  def handle_event("save_rule", %{"alert_rule" => rule_params}, socket) do
    case Monitoring.create_rule(rule_params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rule created successfully")
         |> push_patch(to: ~p"/alerts")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("validate_rule", %{"alert_rule" => rule_params}, socket) do
    changeset =
      %AlertRule{}
      |> AlertRule.changeset(rule_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
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
          <span class={["badge", alert.type == "offline" && "badge-error"]}>{alert.type}</span>
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
        <.simple_form for={@form} phx-change="validate_rule" phx-submit="save_rule">
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
      </.modal>
    </div>
    """
  end
end
