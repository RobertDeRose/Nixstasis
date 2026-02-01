defmodule NixstasisWeb.DeviceLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device

  def mount(_params, _session, socket) do
    {:ok, stream(socket, :devices, Devices.list_devices())}
  end

  def render(assigns) do
    ~H"""
    <.header>
      Devices
      <:actions>
        <.link patch={~p"/devices/new"}>
          <.button>New Device</.button>
        </.link>
      </:actions>
    </.header>

    <.table
      id="devices"
      rows={@streams.devices}
    >
      <:col :let={{_id, device}} label="MAC Address">{device.mac_address}</:col>
      <:col :let={{_id, device}} label="Product">{device.product_key}</:col>
      <:col :let={{_id, device}} label="Status">
        <span class={["badge",
          device.approval_status == "approved" && "badge-success",
          device.approval_status == "pending" && "badge-warning",
          device.approval_status == "rejected" && "badge-error"
        ]}>{device.approval_status}</span>
      </:col>
      <:col :let={{_id, device}} label="Last Seen">{device.last_seen_at}</:col>
    </.table>

    <.modal :if={@live_action == :new} id="device-modal" show on_cancel={JS.patch(~p"/devices")}>
      <.header>
        New Device
        <:subtitle>Pre-register a device by MAC address.</:subtitle>
      </.header>
      <.simple_form
        for={@form}
        id="device-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:mac_address]} label="MAC Address" />
        <.input field={@form[:product_key]} label="Product Key" />
        <.input field={@form[:approval_status]} type="select" label="Status" options={["pending", "approved", "rejected"]} />

        <:actions>
          <.button phx-disable-with="Saving...">Save Device</.button>
        </:actions>
      </.simple_form>
    </.modal>
    """
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Device")
    |> assign(:device, %Device{})
    |> assign(:form, to_form(Devices.change_device(%Device{})))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Devices")
    |> assign(:device, nil)
  end

  def handle_event("validate", %{"device" => device_params}, socket) do
    changeset =
      socket.assigns.device
      |> Devices.change_device(device_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"device" => device_params}, socket) do
    case Devices.create_device(device_params) do
      {:ok, device} ->
        {:noreply,
         socket
         |> put_flash(:info, "Device created successfully")
         |> stream_insert(:devices, device)
         |> push_patch(to: ~p"/devices")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
