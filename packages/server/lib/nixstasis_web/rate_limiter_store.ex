defmodule NixstasisWeb.RateLimiterStore do
  @moduledoc false

  use GenServer

  @table :nixstasis_rate_limiter
  @bounded_table :nixstasis_preauth_rate_limiter
  @prune_interval_ms 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def check_rate(key, limit, window_ms) do
    check_table_rate(@table, key, limit, window_ms)
  end

  @doc false
  def check_bounded_rate(key, limit, window_ms, max_keys)
      when is_integer(max_keys) and max_keys > 0 do
    now = System.monotonic_time(:millisecond)

    case active_counter(@bounded_table, key, now, window_ms) do
      {:active, count} ->
        if count > limit, do: :limited, else: :ok

      :missing_or_expired ->
        GenServer.call(__MODULE__, {:check_bounded_rate, key, limit, window_ms, max_keys, now})
    end
  end

  @doc false
  def clear do
    :ets.delete_all_objects(@table)
    :ets.delete_all_objects(@bounded_table)
    :ok
  end

  @doc false
  def bounded_size, do: :ets.info(@bounded_table, :size)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(@bounded_table, [:named_table, :public, :set, read_concurrency: true])
    schedule_prune()
    {:ok, %{max_window_ms: max_window_ms()}}
  end

  @impl true
  def handle_call({:check_bounded_rate, key, limit, window_ms, max_keys, now}, _from, state) do
    result =
      case active_counter(@bounded_table, key, now, window_ms) do
        {:active, count} ->
          if count > limit, do: :limited, else: :ok

        :missing_or_expired ->
          if not :ets.member(@bounded_table, key) and :ets.info(@bounded_table, :size) >= max_keys do
            prune_table(@bounded_table, now - window_ms)
          end

          if :ets.member(@bounded_table, key) or :ets.info(@bounded_table, :size) < max_keys do
            :ets.insert(@bounded_table, {key, now, 1})
            :ok
          else
            :limited
          end
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:prune, state) do
    cutoff = System.monotonic_time(:millisecond) - state.max_window_ms

    prune_table(@table, cutoff)
    prune_table(@bounded_table, cutoff)
    schedule_prune()

    {:noreply, state}
  end

  defp check_table_rate(table, key, limit, window_ms) do
    now = System.monotonic_time(:millisecond)

    case active_counter(table, key, now, window_ms) do
      {:active, count} ->
        if count > limit, do: :limited, else: :ok

      :missing_or_expired ->
        :ets.insert(table, {key, now, 1})
        :ok
    end
  end

  defp active_counter(table, key, now, window_ms) do
    case :ets.lookup(table, key) do
      [{^key, window_started_at, _count}] when now - window_started_at < window_ms ->
        try do
          {:active, :ets.update_counter(table, key, {3, 1})}
        rescue
          ArgumentError -> :missing_or_expired
        end

      _ ->
        :missing_or_expired
    end
  end

  defp prune_table(table, cutoff) do
    :ets.select_delete(table, [{{:"$1", :"$2", :"$3"}, [{:"=<", :"$2", cutoff}], [true]}])
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, @prune_interval_ms)

  defp max_window_ms do
    :nixstasis
    |> Application.get_env(:rate_limit, [])
    |> Keyword.get(:window_ms, 60_000)
  end
end
