defmodule NixstasisWeb.SettingsLive do
  use NixstasisWeb, :live_view
  alias Nixstasis.Settings

  def mount(_params, _session, socket) do
    window = Settings.get_offline_window()
    notifications = Settings.get_notifications_config()

    socket =
      socket
      |> assign(:offline_window, window)
      |> assign(:palette_options, palette_options())
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
    <div class="ui-page-shell-narrow">
      <.header>
        Settings
        <:subtitle>System configuration</:subtitle>
      </.header>

      <div class="mt-6 space-y-8">
        <section class="ui-card-panel p-6">
          <h3 class="text-lg font-medium">Appearance</h3>
          <p class="mt-1 text-sm text-base-content/70">
            Choose the app color palette. Light, dark, and system mode still use the theme toggle.
          </p>
          <div id="palette-select-wrapper" class="ui-fieldset mt-4" phx-update="ignore">
            <label for="palette-select" class="ui-label">Color Palette</label>
            <select id="palette-select" class="select w-full" data-palette-select>
              <option
                :for={{label, value} <- @palette_options}
                value={value}
                selected={value == "coherent-current"}
              >
                {label}
              </option>
            </select>
            <p class="ui-help-text mt-2">Default: Coherent Current</p>
          </div>
        </section>

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
    </div>
    """
  end

  defp palette_options do
    [
      {"Coherent Current", "coherent-current"},
      {"Glacier Console", "glacier-console"},
      {"Signal Slate", "signal-slate"},
      {"Deepwater Operations", "deepwater-operations"},
      {"Mineral Glass", "mineral-glass"},
      {"Northstar Amber", "northstar-amber"},
      {"Electric Fjord", "electric-fjord"},
      {"Quiet Instrument", "quiet-instrument"},
      {"Aurora Control", "aurora-control"},
      {"Maglev Neon", "maglev-neon"}
    ]
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
