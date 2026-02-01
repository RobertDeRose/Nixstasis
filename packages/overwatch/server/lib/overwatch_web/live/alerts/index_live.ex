defmodule NixstasisWeb.AlertLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.Repo
  import Ecto.Query
  alias Nixstasis.Monitoring.Alert

  def mount(_params, _session, socket) do
    # Simple list for now
    alerts =
      from(a in Alert, order_by: [desc: a.triggered_at], preload: [:device])
      |> Repo.all()

    {:ok, stream(socket, :alerts, alerts)}
  end

  def render(assigns) do
    ~H"""
    <.header>
      Alerts
      <:subtitle>System notifications and device alerts</:subtitle>
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
    """
  end
end
