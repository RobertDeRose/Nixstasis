defmodule Nixstasis.E2E.RetentionWorker do
  @moduledoc """
  Periodically enforces E2E run/log retention policy.
  """

  use GenServer

  require Logger

  alias Nixstasis.E2E

  @default_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %{interval_ms: retention_check_interval_ms()}
    schedule_prune(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:prune_retention, state) do
    case E2E.prune_retention() do
      {:ok, %{pruned_runs: count, pruned_log_bytes: bytes}} when count > 0 ->
        Logger.info("E2E retention pruned #{count} runs and #{bytes} bytes of logs")

      {:ok, _summary} ->
        :ok

      {:error, reason} ->
        Logger.warning("E2E retention prune failed: #{inspect(reason)}")
    end

    schedule_prune(state.interval_ms)
    {:noreply, state}
  end

  defp schedule_prune(interval_ms) do
    Process.send_after(self(), :prune_retention, interval_ms)
  end

  defp retention_check_interval_ms do
    Application.get_env(:nixstasis, :e2e, [])
    |> Keyword.get(:retention, [])
    |> Keyword.get(:check_interval_ms, @default_interval_ms)
  end
end
