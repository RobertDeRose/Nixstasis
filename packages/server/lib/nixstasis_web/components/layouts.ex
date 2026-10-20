defmodule NixstasisWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use NixstasisWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates("layouts/*")

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash id="flash-device-success" kind={:device_success} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders the desktop sidebar as the main navigation landmark.

  The link for the current page is highlighted and marked `aria-current="page"`.
  Settings sits apart from the workflow pages, and the theme toggle at the
  bottom includes the palette picker.
  """
  def sidebar(assigns) do
    assigns =
      assigns
      |> assign(:current_path, assigns[:current_path] || "")
      |> assign(:nav_items, nav_items())
      |> assign(:settings_item, settings_nav_item())

    ~H"""
    <nav class="drawer-side z-50" aria-label="Main">
      <label for="drawer" aria-label="close sidebar" class="drawer-overlay"></label>
      <div class="menu bg-base-200 text-base-content min-h-full w-fit p-4">
        <div class="mb-8 px-2 flex items-center gap-3">
          <img src={~p"/images/logo.svg"} class="dark:invert" width="40" alt="Nixstasis Logo" />
          <div>
            <div class="font-bold text-xl tracking-tight">Nixstasis</div>
            <div class="text-xs opacity-70">Atomic Coherence</div>
          </div>
        </div>

        <ul class="menu menu-lg gap-2">
          <li :for={item <- @nav_items}>
            <.nav_link item={item} current_path={@current_path}>
              <.icon name={item.icon} class="size-5" /> {item.label}
            </.nav_link>
          </li>
        </ul>

        <div class="divider"></div>

        <ul class="menu menu-lg gap-2">
          <li>
            <.nav_link item={@settings_item} current_path={@current_path}>
              <.icon name={@settings_item.icon} class="size-5" /> {@settings_item.label}
            </.nav_link>
          </li>
        </ul>

        <div class="mt-auto space-y-4">
          <div class="flex justify-center">
            <.theme_toggle id="sidebar-theme-toggle" show_palette={true} />
          </div>

          <div class="text-xs opacity-70">
            v{Application.spec(:nixstasis, :vsn)}
          </div>
        </div>
      </div>
    </nav>
    """
  end

  @doc """
  Renders the icon-only bottom navigation shown below the `lg` breakpoint.

  It lists the same pages as the sidebar, including Settings, names each icon
  with `aria-label` and a tooltip, and marks the current page.
  """
  def bottom_nav(assigns) do
    assigns =
      assigns
      |> assign(:current_path, assigns[:current_path] || "")
      |> assign(:nav_items, nav_items() ++ [settings_nav_item()])

    ~H"""
    <nav
      class="fixed bottom-4 left-4 right-4 mx-auto max-w-lg shadow-lg rounded-box z-50 bg-base-100 lg:hidden flex justify-center"
      aria-label="Main"
    >
      <ul class="menu menu-horizontal p-1 w-full justify-between flex-nowrap">
        <li :for={item <- @nav_items} class="tooltip tooltip-top" data-tip={item.label}>
          <.nav_link
            item={item}
            current_path={@current_path}
            active_class="menu-active text-primary"
            aria-label={item.label}
          >
            <.icon name={item.icon} class="size-6" />
          </.nav_link>
        </li>
      </ul>
    </nav>
    """
  end

  attr(:item, :map, required: true)
  attr(:current_path, :string, required: true)
  attr(:active_class, :string, default: "menu-active")
  attr(:rest, :global)
  slot(:inner_block, required: true)

  # A navigation link that applies active_class and aria-current="page" when the
  # current path is inside the item's section.
  defp nav_link(assigns) do
    assigns = assign(assigns, :active?, nav_active?(assigns.item.path, assigns.current_path))

    ~H"""
    <.link
      navigate={@item.path}
      class={@active? && @active_class}
      aria-current={@active? && "page"}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # The workflow pages, in navigation order; Settings is listed separately.
  defp nav_items do
    [
      %{path: ~p"/", label: "Dashboard", icon: "hero-home"},
      %{path: ~p"/devices", label: "Devices", icon: "hero-server"},
      %{path: ~p"/alerts", label: "Alerts", icon: "hero-bell"},
      %{path: ~p"/reports", label: "Reports", icon: "hero-chart-bar"},
      %{path: ~p"/scripts", label: "Scripts", icon: "hero-document-text"}
    ]
  end

  # Settings, which the sidebar shows apart from the workflow pages.
  defp settings_nav_item, do: %{path: ~p"/settings", label: "Settings", icon: "hero-cog-6-tooth"}

  # The dashboard is active only on "/"; every other item is active anywhere
  # under its path, so /devices/:id highlights Devices.
  defp nav_active?("/", current_path), do: current_path == "/"
  defp nav_active?(path, current_path), do: String.starts_with?(current_path, path)

  @doc """
  Renders the system, light, and dark theme buttons, plus the palette picker
  when `show_palette` is true.

  The script in `root.html.heex` applies the saved choices before the page
  renders and sets each button's `aria-pressed`, so the toggle is rendered with
  `phx-update="ignore"` and needs a unique `id`.
  """
  @theme_options [
    {"system", "Use system theme", "hero-computer-desktop-micro"},
    {"light", "Use light theme", "hero-sun-micro"},
    {"dark", "Use dark theme", "hero-moon-micro"}
  ]

  attr(:id, :string, required: true)
  attr(:show_palette, :boolean, default: false)

  def theme_toggle(assigns) do
    assigns = assign(assigns, :theme_options, @theme_options)

    # The root layout script owns theme state and sets aria-pressed, so the
    # server must not patch over it.
    ~H"""
    <div
      id={@id}
      phx-update="ignore"
      class={[
        "w-full max-w-44",
        @show_palette && "rounded-2xl border border-base-300 bg-base-300/80 p-1 shadow-sm"
      ]}
    >
      <div
        role="group"
        aria-label="Theme"
        class="relative flex h-9 flex-row items-center rounded-full bg-base-200"
      >
        <div class="absolute h-full w-1/3 rounded-full border border-base-300 bg-base-100 shadow-sm brightness-110 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

        <button
          :for={{theme, label, icon} <- @theme_options}
          type="button"
          class="relative z-10 flex h-full w-1/3 cursor-pointer items-center justify-center rounded-full"
          phx-click={JS.dispatch("phx:set-theme")}
          data-phx-theme={theme}
          aria-label={label}
          aria-pressed="false"
        >
          <.icon name={icon} class="size-4 opacity-75 hover:opacity-100" />
        </button>
      </div>

      <.palette_select
        :if={@show_palette}
        class="select select-xs mt-1 min-h-8 w-full rounded-xl border-base-300 bg-base-100 text-xs font-medium"
        aria-label="Color palette"
      />
    </div>
    """
  end

  @doc """
  Renders the palette picker. The root layout script owns the choice and keeps
  every picker in sync, so callers must render it inside `phx-update="ignore"`.
  """
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  def palette_select(assigns) do
    assigns = assign(assigns, :palette_options, NixstasisWeb.Theme.palettes())

    ~H"""
    <select class={@class} data-palette-select {@rest}>
      <option
        :for={{label, value} <- @palette_options}
        value={value}
        selected={value == NixstasisWeb.Theme.default_palette()}
      >
        {label}
      </option>
    </select>
    """
  end
end
