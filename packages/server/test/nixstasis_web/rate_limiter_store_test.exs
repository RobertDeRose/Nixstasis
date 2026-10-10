defmodule NixstasisWeb.RateLimiterStoreTest do
  use ExUnit.Case, async: false

  alias NixstasisWeb.RateLimiterStore

  setup do
    # Ensure the store is running (started by application supervisor)
    assert Process.whereis(RateLimiterStore)
    # Clear all entries between tests
    RateLimiterStore.clear()
    :ok
  end

  describe "check_rate/3" do
    test "allows requests under the limit" do
      assert :ok = RateLimiterStore.check_rate({:test, "GET", "127.0.0.1"}, 5, 60_000)
      assert :ok = RateLimiterStore.check_rate({:test, "GET", "127.0.0.1"}, 5, 60_000)
      assert :ok = RateLimiterStore.check_rate({:test, "GET", "127.0.0.1"}, 5, 60_000)
    end

    test "blocks requests over the limit" do
      key = {:test, "POST", "10.0.0.1"}

      for _ <- 1..3, do: assert(:ok = RateLimiterStore.check_rate(key, 3, 60_000))

      assert :limited = RateLimiterStore.check_rate(key, 3, 60_000)
    end

    test "resets after window expires" do
      key = {:test, "GET", "expiry"}
      window_ms = 50

      for _ <- 1..2, do: assert(:ok = RateLimiterStore.check_rate(key, 2, window_ms))

      assert :limited = RateLimiterStore.check_rate(key, 2, window_ms)

      Process.sleep(window_ms + 10)

      assert :ok = RateLimiterStore.check_rate(key, 2, window_ms)
    end

    test "different keys are independent" do
      key_a = {:test, "GET", "a"}
      key_b = {:test, "GET", "b"}

      for _ <- 1..2, do: RateLimiterStore.check_rate(key_a, 2, 60_000)

      assert :limited = RateLimiterStore.check_rate(key_a, 2, 60_000)
      assert :ok = RateLimiterStore.check_rate(key_b, 2, 60_000)
    end

    test "concurrent window starts count every accepted request" do
      for round <- 1..50 do
        key = {:test, :concurrent_start, round}
        assert concurrent_accepts(fn -> RateLimiterStore.check_rate(key, 1, 60_000) end) == 1
      end
    end

    test "concurrent resets of an expired window count every accepted request" do
      for round <- 1..50 do
        key = {:test, :concurrent_reset, round}
        :ets.insert(:nixstasis_rate_limiter, {key, System.monotonic_time(:millisecond) - 120_000, 99})
        assert concurrent_accepts(fn -> RateLimiterStore.check_rate(key, 1, 60_000) end) == 1
      end
    end
  end

  defp concurrent_accepts(check, callers \\ 16) do
    tasks =
      for _ <- 1..callers do
        Task.async(fn ->
          receive do
            :go -> check.()
          end
        end)
      end

    for task <- tasks, do: send(task.pid, :go)

    tasks
    |> Task.await_many(5_000)
    |> Enum.count(&(&1 == :ok))
  end

  test "concurrent key deletion does not crash rate checks" do
    supervisor = start_supervised!(Task.Supervisor)
    key = {:test, :deletion_race}
    now = System.monotonic_time(:millisecond)
    tables = [:nixstasis_rate_limiter, :nixstasis_preauth_rate_limiter]

    for table <- tables, do: :ets.insert(table, {key, now, 1})

    deleter =
      Task.Supervisor.async_nolink(supervisor, fn ->
        for _ <- 1..100_000, table <- tables do
          :ets.delete(table, key)
          :ets.insert(table, {key, now, 1})
        end
      end)

    readers =
      for _ <- 1..2 do
        Task.Supervisor.async_nolink(supervisor, fn ->
          for _ <- 1..10_000 do
            assert :ok = RateLimiterStore.check_rate(key, 1_000_000, 60_000)
            assert RateLimiterStore.check_bounded_rate(key, 1_000_000, 60_000, 1) in [:ok, :limited]
          end
        end)
      end

    for task <- [deleter | readers], do: Task.await(task, 30_000)
    assert RateLimiterStore.bounded_size() <= 1
  end

  describe "check_bounded_rate/4" do
    test "caps new key cardinality without evicting active counters" do
      assert :ok = RateLimiterStore.check_bounded_rate({:origin, 1}, 10, 60_000, 2)
      assert :ok = RateLimiterStore.check_bounded_rate({:origin, 2}, 10, 60_000, 2)
      assert :limited = RateLimiterStore.check_bounded_rate({:origin, 3}, 10, 60_000, 2)
      assert RateLimiterStore.bounded_size() == 2

      assert :ok = RateLimiterStore.check_bounded_rate({:origin, 1}, 10, 60_000, 2)
      assert RateLimiterStore.bounded_size() == 2
    end

    test "prunes expired entries at capacity without discarding active quotas" do
      window_ms = 60_000
      now = System.monotonic_time(:millisecond)
      :ets.insert(:nixstasis_preauth_rate_limiter, {{:origin, :expired}, now - window_ms, 1})
      assert :ok = RateLimiterStore.check_bounded_rate({:origin, :active}, 1, window_ms, 2)

      assert :ok = RateLimiterStore.check_bounded_rate({:origin, :new}, 1, window_ms, 2)
      assert RateLimiterStore.bounded_size() == 2
      assert :limited = RateLimiterStore.check_bounded_rate({:origin, :active}, 1, window_ms, 2)
      assert :limited = RateLimiterStore.check_bounded_rate({:origin, :overflow}, 1, window_ms, 2)
    end

    test "does not rescan a full table of active entries for every new origin" do
      assert :ok = RateLimiterStore.check_bounded_rate({:origin, 1}, 10, 60_000, 2)
      assert :ok = RateLimiterStore.check_bounded_rate({:origin, 2}, 10, 60_000, 2)

      store = Process.whereis(RateLimiterStore)
      :erlang.trace_pattern({:ets, :foldl, 3}, true, [:local])
      :erlang.trace(store, true, [:call, {:tracer, self()}])

      on_exit(fn -> :erlang.trace_pattern({:ets, :foldl, 3}, false, [:local]) end)

      for origin <- 3..7 do
        assert :limited = RateLimiterStore.check_bounded_rate({:origin, origin}, 10, 60_000, 2)
      end

      :erlang.trace(store, false, [:call])

      assert_received {:trace, ^store, :call, {:ets, :foldl, _}}
      refute_received {:trace, ^store, :call, {:ets, :foldl, _}}
    end

    test "reclaims expired entries once the oldest window at capacity expires" do
      window_ms = 50
      assert :ok = RateLimiterStore.check_bounded_rate({:origin, 1}, 10, window_ms, 1)
      assert :limited = RateLimiterStore.check_bounded_rate({:origin, 2}, 10, window_ms, 1)

      Process.sleep(window_ms + 10)

      assert :ok = RateLimiterStore.check_bounded_rate({:origin, 2}, 10, window_ms, 1)
      assert RateLimiterStore.bounded_size() == 1
    end

    test "reuses an expired key without consuming additional cardinality" do
      key = {:origin, :expiry}
      assert :ok = RateLimiterStore.check_bounded_rate(key, 1, 10, 1)
      Process.sleep(20)
      assert :ok = RateLimiterStore.check_bounded_rate(key, 1, 10, 1)
      assert RateLimiterStore.bounded_size() == 1
    end
  end
end
