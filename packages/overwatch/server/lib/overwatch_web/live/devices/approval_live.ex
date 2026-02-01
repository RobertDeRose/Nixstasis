defmodule NixstasisWeb.DeviceLive.Approval do
  use NixstasisWeb, :live_view

  alias Nixstasis.Devices

  def mount(_params, _session, socket) do
    # In a real app we might subscribe to PubSub here
    # if connected?(socket), do: Phoenix.PubSub.subscribe(Nixstasis.PubSub, "devices")

    {:ok, stream(socket, :devices, Devices.list_pending_devices())}
  end

  def render(assigns) do
    ~H"""
    <.header>
      Pending Approvals
      <:subtitle>Review and approve new devices</:subtitle>
    </.header>

    <.table
      id="devices"
      rows={@streams.devices}
    >
      <:col :let={{_id, device}} label="MAC Address">{device.mac_address}</:col>
      <:col :let={{_id, device}} label="Product">{device.product_key}</:col>
      <:col :let={{_id, device}} label="Status">
        <span class="badge badge-warning">{device.approval_status}</span>
      </:col>
      <:action :let={{_id, device}}>
        <.link
          phx-click={JS.push("approve", value: %{id: device.id})}
          data-confirm="Are you sure you want to approve this device?"
          class="btn btn-sm btn-success"
        >
          Approve
        </.link>
      </:action>
    </.table>
    """
  end

  def handle_event("approve", %{"id" => id}, socket) do
    device = Devices.get_device!(id)

    case Devices.approve_device(device) do
      {:ok, approved_device} ->
        # Remove from pending list
        {:noreply, stream_delete(socket, :devices, approved_device)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to approve device")}
    end
  end
end
