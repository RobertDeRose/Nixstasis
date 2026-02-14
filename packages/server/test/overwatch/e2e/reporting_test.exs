defmodule Nixstasis.E2E.ReportingTest do
  use Nixstasis.DataCase, async: true

  alias Nixstasis.E2E.Reporting
  alias Nixstasis.E2E.Run

  test "summary includes timing fields when timestamps exist" do
    started_at = DateTime.utc_now() |> DateTime.add(-2, :second)
    finished_at = DateTime.utc_now()

    run = %Run{
      id: "run-1",
      suite_id: "full",
      environment_label: "local",
      started_at: started_at,
      finished_at: finished_at
    }

    summary = Reporting.summary(run, [])

    assert is_integer(summary.run_duration_ms)
    assert summary.run_duration_ms >= 0
    assert is_integer(summary.report_latency_ms)
  end
end
