defmodule Nixstasis.E2E.MetricsTest do
  use Nixstasis.DataCase, async: true

  alias Nixstasis.E2E.Metrics
  alias Nixstasis.E2E.RunResult

  test "flaky_rate counts flaky failures" do
    results = [
      %RunResult{status: "failed", failure_reason: "flaky timeout"},
      %RunResult{status: "failed", failure_reason: "deterministic error"},
      %RunResult{status: "passed", failure_reason: nil}
    ]

    assert Metrics.flaky_rate(results) == 1 / 3
  end

  test "flaky_rate is zero when no results" do
    assert Metrics.flaky_rate([]) == 0.0
  end
end
