defmodule Nixstasis.Monitoring.TelemetryRetentionWorker do
  @moduledoc """
  Periodically removes telemetry outside the configured retention window.
  """

  use GenServer

  require Logger

  alias Nixstasis.Monitoring

  @default_interval_ms 86_400_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %{interval_ms: check_interval_ms()}
    schedule_prune(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:prune_retention, state) do
    case Monitoring.prune_telemetry_events() do
      {:ok, %{pruned_events: count}} when count > 0 ->
        Logger.info("Telemetry retention pruned #{count} events")

      {:ok, _summary} ->
        :ok

      {:error, reason} ->
        Logger.warning("Telemetry retention prune failed: #{inspect(reason)}")
    end

    schedule_prune(state.interval_ms)
    {:noreply, state}
  end

  defp schedule_prune(interval_ms) do
    Process.send_after(self(), :prune_retention, interval_ms)
  end

  defp check_interval_ms do
    Application.get_env(:nixstasis, :telemetry_retention, [])
    |> Keyword.get(:check_interval_ms, @default_interval_ms)
  end
end
