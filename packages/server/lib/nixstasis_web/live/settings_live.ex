defmodule NixstasisWeb.SettingsLive do
  use NixstasisWeb, :live_view

  alias Nixstasis.Settings
  alias NixstasisWeb.Permissions

  @doc """
  Opens global settings only for a session with settings-management permission.

  Initializes safe form defaults before authorization, then loads monitoring and
  notification settings for an authorized operator. The stored webhook URL is
  never put into the form. Other operators receive an error and a redirect home.
  """
  @impl true
  def mount(_params, session, socket) do
    permissions = Permissions.settings_permissions(session)

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:settings_permissions, permissions)
      |> assign(:highlights, NixstasisWeb.Theme.highlights())
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

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:class, :any, default: nil)

  # One highlight swatch: a radio styled as a pill. The default shows the active
  # palette's own colour; the others preview their highlight.
  defp highlight_option(assigns) do
    assigns = assign(assigns, :default?, assigns.value == NixstasisWeb.Theme.default_highlight())

    ~H"""
    <label data-highlight-preview={!@default? && @value} class={["block cursor-pointer", @class]}>
      <input
        type="radio"
        name="highlight"
        value={@value}
        class="peer sr-only"
        data-highlight-select
        checked={@default?}
      />
      <span class="flex items-center gap-2 whitespace-nowrap rounded-full border border-base-300 py-1 pl-1 pr-3 text-sm peer-checked:border-primary peer-checked:ring-2 peer-checked:ring-primary peer-focus-visible:outline-3 peer-focus-visible:outline-offset-3 peer-focus-visible:outline-primary">
        <span
          class={["size-6 shrink-0 rounded-full", if(@default?, do: "bg-(--palette-primary)", else: "bg-primary")]}
          aria-hidden="true"
        ></span>
        {@label}
      </span>
    </label>
    """
  end

  @doc """
  Renders the appearance, monitoring, and notification settings forms.

  Appearance holds the palette picker and the highlight swatches. Both are
  saved in the browser by the root layout script, not on the server, so they
  render with `phx-update="ignore"`.

  A configured webhook is represented only by a status message and a removal
  control, not its secret-bearing URL. The replacement field starts blank so
  submitting unrelated settings can preserve the existing destination.
  """
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
            Saved in this browser. Light and dark mode are in the theme toggle; a highlight colour replaces the
            palette's own accent. The High Contrast palette keeps its own colours.
          </p>
          <%!-- The root layout script owns these choices, so the server must not patch over them. --%>
          <div id="palette-picker" class="ui-fieldset mt-4" phx-update="ignore">
            <label for="palette-select" class="ui-label-strong">Colour palette</label>
            <Layouts.palette_select id="palette-select" class="select mt-2 w-full sm:w-64" />
          </div>
          <fieldset id="highlight-picker" class="mt-4" phx-update="ignore">
            <legend class="ui-label-strong">Highlight colour</legend>
            <div class="mt-2 space-y-2">
              <.highlight_option
                :for={{label, value} <- Enum.take(@highlights, 1)}
                label={label}
                value={value}
                class="w-fit"
              />
              <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
                <.highlight_option :for={{label, value} <- Enum.drop(@highlights, 1)} label={label} value={value} />
              </div>
            </div>
          </fieldset>
        </section>

        <div>
          <h3 class="text-lg font-medium">Monitoring</h3>
          <.simple_form id="monitoring-settings-form" for={@form} phx-submit="save_monitoring">
            <.input field={@form[:minutes]} type="number" min="1" step="1" label="Offline Detection Window (minutes)" />
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

  @doc """
  Handles monitoring and notification saves after rechecking management permission.

  Monitoring input uses shared positive-minute validation. Notification input
  can preserve, replace, or explicitly clear a webhook; invalid replacements
  remain in the form for correction. Successful writes update assigns and show
  confirmation, while failures show an error without claiming a successful save.
  For authorized saves, failures clear earlier success feedback and later
  successes clear earlier errors. Unauthorized events leave settings unchanged.
  Returns `{:noreply, socket}`.
  """
  @impl true
  def handle_event("save_monitoring", %{"minutes" => minutes}, socket) do
    if can_manage?(socket) do
      case Settings.put_offline_window(socket.assigns.settings_permissions, minutes) do
        {:ok, setting} ->
          {:noreply,
           socket
           |> clear_flash(:error)
           |> put_flash(:info, "Monitoring settings updated")
           |> assign(:offline_window, setting.value["minutes"])}

        {:error, _reason} ->
          {:noreply,
           socket
           |> clear_flash(:info)
           |> put_flash(:error, "Unable to update monitoring settings")}
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
           |> clear_flash(:error)
           |> put_flash(:info, "Notification settings updated")
           |> assign(:webhook_configured, webhook_configured?(notifications))
           |> assign(:form, settings_form(socket.assigns.offline_window, notifications))}

        {:error, %Ash.Error.Invalid{}} ->
          {:noreply,
           socket
           |> clear_flash(:info)
           |> put_flash(:error, "Webhook URL must use HTTPS and resolve only to public network addresses")
           |> assign(
             :form,
             params
             |> Map.put("minutes", socket.assigns.offline_window)
             |> Map.put_new("clear_webhook_url", "false")
             |> to_form()
           )}

        {:error, _reason} ->
          {:noreply,
           socket
           |> clear_flash(:info)
           |> put_flash(:error, "Unable to update notification settings")}
      end
    else
      unauthorized(socket)
    end
  end

  # Check the mounted permission again for each save event, not just page access.
  defp can_manage?(socket), do: socket.assigns.settings_permissions["can_manage"] == true

  # Reject a settings event with an error flash and no write or success message.
  defp unauthorized(socket) do
    {:noreply, put_flash(socket, :error, "Not authorized to manage system settings")}
  end

  # Populate editable minutes and email, but never copy the stored webhook URL
  # into browser HTML. Replacement and removal begin blank and false respectively.
  defp settings_form(window, notifications) do
    to_form(%{
      "minutes" => window,
      "email" => Map.get(notifications, "email"),
      "webhook_url" => "",
      "clear_webhook_url" => false
    })
  end

  # Expose only whether a nonblank webhook is stored, not the URL or its tokens.
  defp webhook_configured?(notifications) do
    case Map.get(notifications, "webhook_url") do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end
end
