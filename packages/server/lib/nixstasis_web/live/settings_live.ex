defmodule NixstasisWeb.SettingsLive do
  use NixstasisWeb, :live_view

  alias Nixstasis.Settings
  alias NixstasisWeb.Permissions

  @impl true
  def mount(_params, session, socket) do
    permissions = Permissions.settings_permissions(session)

    socket =
      socket
      |> assign(:settings_permissions, permissions)
      |> assign(:palette_options, palette_options())
      |> assign(:offline_window, 10)
      |> assign(:webhook_configured, false)
      |> assign(:form, settings_form(10, %{}))

    if Permissions.can_manage_settings?(session) do
      window = Settings.get_offline_window()
      notifications = Settings.get_notifications_config()

      {:ok,
       socket
       |> assign(:offline_window, window)
       |> assign(:webhook_configured, webhook_configured?(notifications))
       |> assign(:form, settings_form(window, notifications))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Not authorized to manage system settings")
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
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
          <.simple_form id="monitoring-settings-form" for={@form} phx-submit="save_monitoring">
            <.input field={@form[:minutes]} type="number" label="Offline Detection Window (minutes)" />
            <:actions>
              <.button>Save Monitoring Settings</.button>
            </:actions>
          </.simple_form>
        </div>

        <div>
          <h3 class="text-lg font-medium">Notifications</h3>
          <.simple_form id="notification-settings-form" for={@form} phx-submit="save_notifications">
            <.input field={@form[:email]} type="email" label="Alert Email Recipient" />
            <.input field={@form[:webhook_url]} type="url" label="New Webhook URL" />
            <p :if={@webhook_configured} class="ui-help-text">
              A webhook is configured. Its stored URL is not displayed. Leave this field blank to keep it.
            </p>
            <p :if={!@webhook_configured} class="ui-help-text">
              Webhooks must use HTTPS and resolve only to public network addresses.
            </p>
            <.input
              :if={@webhook_configured}
              field={@form[:clear_webhook_url]}
              type="checkbox"
              label="Remove configured webhook"
            />
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

  @impl true
  def handle_event("save_monitoring", %{"minutes" => minutes}, socket) do
    if can_manage?(socket) do
      case Settings.put_offline_window(socket.assigns.settings_permissions, minutes) do
        {:ok, _setting} ->
          {:noreply,
           socket
           |> put_flash(:info, "Monitoring settings updated")
           |> assign(:offline_window, minutes)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Unable to update monitoring settings")}
      end
    else
      unauthorized(socket)
    end
  end

  @impl true
  def handle_event("save_notifications", params, socket) do
    if can_manage?(socket) do
      case Settings.put_notifications_config(socket.assigns.settings_permissions, params) do
        {:ok, _setting} ->
          notifications = Settings.get_notifications_config()

          {:noreply,
           socket
           |> put_flash(:info, "Notification settings updated")
           |> assign(:webhook_configured, webhook_configured?(notifications))
           |> assign(:form, settings_form(socket.assigns.offline_window, notifications))}

        {:error, {:invalid_webhook_url, _reason}} ->
          {:noreply,
           socket
           |> put_flash(:error, "Webhook URL must use HTTPS and resolve only to public network addresses")
           |> assign(
             :form,
             params
             |> Map.put("minutes", socket.assigns.offline_window)
             |> Map.put_new("clear_webhook_url", "false")
             |> to_form()
           )}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Unable to update notification settings")}
      end
    else
      unauthorized(socket)
    end
  end

  defp can_manage?(socket), do: socket.assigns.settings_permissions["can_manage"] == true

  defp unauthorized(socket) do
    {:noreply, put_flash(socket, :error, "Not authorized to manage system settings")}
  end

  defp settings_form(window, notifications) do
    to_form(%{
      "minutes" => window,
      "email" => Map.get(notifications, "email"),
      "webhook_url" => "",
      "clear_webhook_url" => false
    })
  end

  defp webhook_configured?(notifications) do
    case Map.get(notifications, "webhook_url") do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end
end
