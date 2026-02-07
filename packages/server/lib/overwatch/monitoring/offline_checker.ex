defmodule Nixstasis.Monitoring.OfflineChecker do
  @moduledoc """
  Periodically checks for devices that have gone offline.
  """

  use GenServer
  alias Nixstasis.Monitoring

  # Check every minute
  @interval 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    # Start timer
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    # Default window 10 mins. Ideally fetched from config/DB.
    Monitoring.check_offline_devices(window_minutes: 10)
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end
end
