defmodule NixstasisWeb.DeviceLive.FormComponent do
  use NixstasisWeb, :live_component

  alias Nixstasis.Devices

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Add a device here to have to automatically approved when it attempts to register
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        as={:device}
        id="device-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:mac_address]} type="text" label="MAC Address" />
        <.input field={@form[:account_number]} type="text" label="Account Number (Optional)" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Device</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{device: device} = assigns, socket) do
    form = Devices.change_device(device)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(form)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    device_params = params["device"] || params["form"] || %{}
    form = AshPhoenix.Form.validate(socket.assigns.form, device_params)
    {:noreply, assign_form(socket, form)}
  end

  def handle_event("save", params, socket) do
    device_params = params["device"] || params["form"] || %{}
    save_device(socket, socket.assigns.action, device_params)
  end

  defp save_device(socket, :new, device_params) do
    # Inject defaults for manual entry
    device_params =
      device_params
      |> Map.put_new("product_name", "manual-entry")
      |> Map.put_new("approval_status", "approved")

    case AshPhoenix.Form.submit(socket.assigns.form, params: device_params) do
      {:ok, device} ->
        notify_parent({:saved, device})

        {:noreply,
         socket
         |> put_flash(:info, "Device created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, form} ->
        {:noreply, assign_form(socket, form)}
    end
  end

  defp assign_form(socket, %Phoenix.HTML.Form{} = form) do
    assign(socket, :form, form)
  end

  defp assign_form(socket, form) do
    assign(socket, :form, to_form(form))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
