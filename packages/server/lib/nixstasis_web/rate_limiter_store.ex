defmodule NixstasisWeb.RateLimiterStore do
  @moduledoc false

  use GenServer

  @table :nixstasis_rate_limiter
  @prune_interval_ms 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def check_rate(key, limit, window_ms) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, window_started_at, _count}] when now - window_started_at < window_ms ->
        count = :ets.update_counter(@table, key, {3, 1})
        if count > limit, do: :limited, else: :ok

      _ ->
        :ets.insert(@table, {key, now, 1})
        :ok
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_prune()
    {:ok, %{max_window_ms: max_window_ms()}}
  end

  @impl true
  def handle_info(:prune, state) do
    cutoff = System.monotonic_time(:millisecond) - state.max_window_ms

    :ets.select_delete(@table, [{{:"$1", :"$2", :"$3"}, [{:<, :"$2", cutoff}], [true]}])
    schedule_prune()

    {:noreply, state}
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, @prune_interval_ms)

  defp max_window_ms do
    :nixstasis
    |> Application.get_env(:rate_limit, [])
    |> Keyword.get(:window_ms, 60_000)
  end
end
