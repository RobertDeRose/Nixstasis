defmodule NixstasisWeb.DashboardLive.Index do
  use NixstasisWeb, :live_view

  require Logger

  alias Nixstasis.Dashboard

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Nixstasis.PubSub, "devices")
      Phoenix.PubSub.subscribe(Nixstasis.PubSub, "alerts")
    end

    {:ok, assign(socket, stats: Dashboard.get_vital_stats(), loading: false)}
  end

  @refresh_debounce_ms 5_000

  @impl true
  def handle_info({:device_last_seen_updated, _device}, socket) do
    {:noreply, schedule_debounced_refresh(socket)}
  end

  def handle_info({event, _device}, socket)
      when event in [
             :device_registered,
             :device_created,
             :device_updated,
             :device_approval_status_changed,
             :device_remote_access_changed
           ] do
    {:noreply, assign(socket, :stats, Dashboard.get_vital_stats())}
  end

  def handle_info({:alert_created, _alert}, socket) do
    {:noreply, assign(socket, :stats, Dashboard.get_vital_stats())}
  end

  def handle_info(:debounced_refresh, socket) do
    {:noreply,
     socket
     |> assign(:refresh_timer, nil)
     |> assign(:stats, Dashboard.get_vital_stats())}
  end

  def handle_info(message, socket) do
    Logger.debug("#{__MODULE__} unhandled message: #{inspect(message)}")
    {:noreply, socket}
  end

  defp schedule_debounced_refresh(socket) do
    existing = Map.get(socket.assigns, :refresh_timer)

    if existing do
      socket
    else
      timer = Process.send_after(self(), :debounced_refresh, @refresh_debounce_ms)
      assign(socket, :refresh_timer, timer)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl">
      <h1 class="text-3xl font-bold mb-6">Overview</h1>

      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <%= if @loading do %>
          <div class="col-span-full flex justify-center p-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <.link navigate="/devices">
            <NixstasisWeb.Components.StatsCard.stats_card
              title="Total Devices"
              value={"#{@stats.total_devices}"}
            />
          </.link>

          <.link navigate="/devices?connectivity_status=online">
            <NixstasisWeb.Components.StatsCard.stats_card
              title="Online"
              value={"#{@stats.online_devices}"}
              desc={"Offline: #{@stats.offline_devices}"}
              color_class="text-success"
            />
          </.link>

          <.link navigate="/devices?approval_status=pending">
            <NixstasisWeb.Components.StatsCard.stats_card
              title="Pending Approvals"
              value={"#{@stats.pending_approvals}"}
              color_class="text-yellow-600 dark:text-yellow-400"
            />
          </.link>

          <.link navigate="/alerts?status=active">
            <NixstasisWeb.Components.StatsCard.stats_card
              title="Active Alerts"
              value={"#{@stats.active_alerts}"}
              color_class="text-error"
            />
          </.link>
        <% end %>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <.link navigate="/devices" class="btn btn-primary h-auto py-4 flex flex-col gap-2">
          <span class="text-lg">Manage Devices</span>
          <span class="text-xs font-normal opacity-80">View and configure fleet</span>
        </.link>

        <.link
          navigate="/devices?approval_status=pending"
          class="btn btn-secondary h-auto py-4 flex flex-col gap-2"
        >
          <span class="text-lg">Pending Approvals</span>
          <span class="text-xs font-normal opacity-80">Review new registrations</span>
        </.link>

        <.link navigate="/alerts" class="btn btn-accent h-auto py-4 flex flex-col gap-2">
          <span class="text-lg">View Alerts</span>
          <span class="text-xs font-normal opacity-80">Monitor critical events</span>
        </.link>

        <.link navigate="/reports" class="btn btn-neutral h-auto py-4 flex flex-col gap-2">
          <span class="text-lg">Reports</span>
          <span class="text-xs font-normal opacity-80">Analyze fleet data</span>
        </.link>
      </div>
    </div>
    """
  end
end
