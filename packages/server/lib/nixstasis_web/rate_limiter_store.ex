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
    GenServer.call(__MODULE__, :reset_bounded_prune)
  end

  @doc false
  def bounded_size, do: :ets.info(@bounded_table, :size)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(@bounded_table, [:named_table, :public, :set, read_concurrency: true])
    schedule_prune()
    {:ok, %{max_window_ms: max_window_ms(), next_bounded_prune_at: nil}}
  end

  @impl true
  def handle_call(:reset_bounded_prune, _from, state) do
    {:reply, :ok, %{state | next_bounded_prune_at: nil}}
  end

  @impl true
  def handle_call({:check_bounded_rate, key, limit, window_ms, max_keys, now}, _from, state) do
    case active_counter(@bounded_table, key, now, window_ms) do
      {:active, count} ->
        {:reply, if(count > limit, do: :limited, else: :ok), state}

      :missing_or_expired ->
        state =
          if not :ets.member(@bounded_table, key) and :ets.info(@bounded_table, :size) >= max_keys do
            maybe_prune_bounded(state, now, window_ms)
          else
            state
          end

        result =
          if :ets.member(@bounded_table, key) or :ets.info(@bounded_table, :size) < max_keys do
            if count_request(@bounded_table, key, now, window_ms) > limit, do: :limited, else: :ok
          else
            :limited
          end

        {:reply, result, state}
    end
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

    if count_request(table, key, now, window_ms) > limit, do: :limited, else: :ok
  end

  # Counts one request, atomically starting a new window when the key is
  # missing or expired so concurrent resets cannot discard accepted requests.
  defp count_request(table, key, now, window_ms) do
    case active_counter(table, key, now, window_ms) do
      {:active, count} ->
        count

      :missing_or_expired ->
        case start_window(table, key, now, window_ms) do
          :started -> 1
          :retry -> count_request(table, key, now, window_ms)
        end
    end
  end

  defp start_window(table, key, now, window_ms) do
    if :ets.insert_new(table, {key, now, 1}) do
      :started
    else
      case :ets.lookup(table, key) do
        [{^key, window_started_at, _count}] when now - window_started_at >= window_ms ->
          # Compare-and-swap: replace only the exact expired window observed.
          match_spec = [{{key, window_started_at, :_}, [], [{{{:const, key}, now, 1}}]}]

          if :ets.select_replace(table, match_spec) == 1, do: :started, else: :retry

        _ ->
          :retry
      end
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

  # At capacity, skip the full-table scan until the oldest remaining window can
  # have expired, so a flood of new origins cannot rescan an all-active table on
  # every request inside this singleton process.
  defp maybe_prune_bounded(%{next_bounded_prune_at: next} = state, now, _window_ms)
       when is_integer(next) and now < next,
       do: state

  defp maybe_prune_bounded(state, now, window_ms) do
    prune_table(@bounded_table, now - window_ms)

    oldest_started_at =
      :ets.foldl(
        fn {_key, started_at, _count}, oldest -> min(started_at, oldest) end,
        :infinity,
        @bounded_table
      )

    next = if is_integer(oldest_started_at), do: oldest_started_at + window_ms
    %{state | next_bounded_prune_at: next}
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
