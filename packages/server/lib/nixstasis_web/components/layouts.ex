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
  Renders the sidebar navigation.
  """
  def sidebar(assigns) do
    assigns = assign(assigns, :current_path, assigns[:current_path] || "")

    ~H"""
    <div class="drawer-side z-50">
      <label for="drawer" aria-label="close sidebar" class="drawer-overlay"></label>
      <div class="menu bg-base-200 text-base-content min-h-full w-fit p-4">
        <div class="mb-8 px-2 flex items-center gap-3">
          <img src={~p"/images/logo.svg"} class="dark:invert" width="40" alt="Nixstasis Logo" />
          <div>
            <div class="font-bold text-xl tracking-tight">Nixstasis</div>
            <div class="text-xs opacity-60">Atomic Coherence</div>
          </div>
        </div>

        <ul class="menu menu-lg gap-2">
          <li>
            <.link navigate={~p"/"} class={if @current_path == "/", do: "active"}>
              <.icon name="hero-home" class="size-5" /> Dashboard
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/devices"}
              class={if String.starts_with?(@current_path, "/devices"), do: "active"}
            >
              <.icon name="hero-server" class="size-5" /> Devices
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/alerts"}
              class={if String.starts_with?(@current_path, "/alerts"), do: "active"}
            >
              <.icon name="hero-bell" class="size-5" /> Alerts
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/reports"}
              class={if String.starts_with?(@current_path, "/reports"), do: "active"}
            >
              <.icon name="hero-chart-bar" class="size-5" /> Reports
            </.link>
          </li>
        </ul>

        <div class="divider"></div>

        <ul class="menu menu-lg gap-2">
          <li>
            <.link
              navigate={~p"/settings"}
              class={if String.starts_with?(@current_path, "/settings"), do: "active"}
            >
              <.icon name="hero-cog-6-tooth" class="size-5" /> Settings
            </.link>
          </li>
        </ul>

        <div class="mt-auto space-y-4">
          <div class="flex justify-center">
            <.theme_toggle />
          </div>

          <div class="text-xs opacity-70">
            v{Application.spec(:nixstasis, :vsn)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the bottom navigation for mobile.
  """
  def bottom_nav(assigns) do
    assigns = assign(assigns, :current_path, assigns[:current_path] || "")

    ~H"""
    <div class="fixed bottom-4 left-4 right-4 mx-auto max-w-lg shadow-lg rounded-box z-50 bg-base-100 lg:hidden flex justify-center">
      <ul class="menu menu-horizontal p-1 w-full justify-between flex-nowrap">
        <li class="tooltip tooltip-top" data-tip="Dashboard">
          <.link
            navigate={~p"/"}
            class={if @current_path == "/", do: "active text-primary"}
            aria-label="Dashboard"
          >
            <.icon name="hero-home" class="size-6" />
          </.link>
        </li>
        <li class="tooltip tooltip-top" data-tip="Devices">
          <.link
            navigate={~p"/devices"}
            class={if String.starts_with?(@current_path, "/devices"), do: "active text-primary"}
            aria-label="Devices"
          >
            <.icon name="hero-server" class="size-6" />
          </.link>
        </li>
        <li class="tooltip tooltip-top" data-tip="Alerts">
          <.link
            navigate={~p"/alerts"}
            class={if String.starts_with?(@current_path, "/alerts"), do: "active text-primary"}
            aria-label="Alerts"
          >
            <.icon name="hero-bell" class="size-6" />
          </.link>
        </li>
        <li class="tooltip tooltip-top" data-tip="Reports">
          <.link
            navigate={~p"/reports"}
            class={if String.starts_with?(@current_path, "/reports"), do: "active text-primary"}
            aria-label="Reports"
          >
            <.icon name="hero-chart-bar" class="size-6" />
          </.link>
        </li>
        <li class="tooltip tooltip-top" data-tip="Settings">
          <.link
            navigate={~p"/settings"}
            class={if String.starts_with?(@current_path, "/settings"), do: "active text-primary"}
            aria-label="Settings"
          >
            <.icon name="hero-cog-6-tooth" class="size-6" />
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
