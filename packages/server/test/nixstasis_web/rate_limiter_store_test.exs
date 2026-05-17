defmodule NixstasisWeb.RateLimiterStoreTest do
  use ExUnit.Case, async: false

  alias NixstasisWeb.RateLimiterStore

  setup do
    # Ensure the store is running (started by application supervisor)
    assert Process.whereis(RateLimiterStore)
    # Clear all entries between tests
    :ets.delete_all_objects(:nixstasis_rate_limiter)
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
  end
end
