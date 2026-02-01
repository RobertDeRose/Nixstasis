defmodule NixstasisWeb.SettingsLive do
  use NixstasisWeb, :live_view
  alias Nixstasis.Settings

  def mount(_params, _session, socket) do
    window = Settings.get_offline_window()
    notifications = Settings.get_notifications_config()

    socket =
      socket
      |> assign(:offline_window, window)
      |> assign(
        :form,
        to_form(%{
          "minutes" => window,
          "email" => notifications["email"],
          "webhook_url" => notifications["webhook_url"]
        })
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.header>
      Settings
      <:subtitle>System configuration</:subtitle>
    </.header>

    <div class="max-w-md mt-6 space-y-8">
      <div>
        <h3 class="text-lg font-medium">Monitoring</h3>
        <.simple_form for={@form} phx-submit="save_monitoring">
          <.input field={@form[:minutes]} type="number" label="Offline Detection Window (minutes)" />
          <:actions>
            <.button>Save Monitoring Settings</.button>
          </:actions>
        </.simple_form>
      </div>

      <div>
        <h3 class="text-lg font-medium">Notifications</h3>
        <.simple_form for={@form} phx-submit="save_notifications">
          <.input field={@form[:email]} type="email" label="Alert Email Recipient" />
          <.input field={@form[:webhook_url]} type="url" label="Webhook URL" />
          <:actions>
            <.button>Save Notification Settings</.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def handle_event("save_monitoring", %{"minutes" => minutes}, socket) do
    Settings.put_setting("offline_window", %{"minutes" => minutes})

    {:noreply,
     socket
     |> put_flash(:info, "Monitoring settings updated")
     |> assign(:offline_window, minutes)}
  end

  def handle_event("save_notifications", params, socket) do
    Settings.put_setting("notifications", %{
      "email" => params["email"],
      "webhook_url" => params["webhook_url"]
    })

    {:noreply, put_flash(socket, :info, "Notification settings updated")}
  end
end
