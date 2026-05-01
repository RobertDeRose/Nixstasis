defmodule Nixstasis.E2E.Reporting do
  @moduledoc """
  Generates summary reports for E2E runs.
  """

  alias Nixstasis.E2E.Run
  alias Nixstasis.E2E.RunResult

  def summary(%Run{} = run, results) do
    counts = Enum.frequencies_by(results, & &1.status)
    reported_at = DateTime.utc_now()

    %{
      run_id: run.id,
      suite_id: run.suite_id,
      environment_label: run.environment_label,
      total: length(results),
      passed: Map.get(counts, "passed", 0),
      failed: Map.get(counts, "failed", 0),
      skipped: Map.get(counts, "skipped", 0),
      queued: Map.get(counts, "queued", 0),
      status: overall_status(counts),
      run_duration_ms: duration_ms(run.started_at, run.finished_at),
      report_generated_at: reported_at,
      report_latency_ms: latency_ms(run.finished_at, reported_at)
    }
  end

  def write_summary(%Run{} = run, results) do
    report_dir = report_dir()
    File.mkdir_p!(report_dir)

    path = Path.join(report_dir, "#{run.id}.json")
    File.write!(path, Jason.encode!(summary(run, results)))
    {:ok, path}
  end

  defp overall_status(counts) do
    total = Enum.reduce(counts, 0, fn {_key, value}, acc -> acc + value end)

    cond do
      Map.get(counts, "failed", 0) > 0 -> "failed"
      Map.get(counts, "running", 0) > 0 -> "running"
      Map.get(counts, "queued", 0) > 0 -> "running"
      Map.get(counts, "blocked", 0) > 0 -> "blocked"
      Map.get(counts, "skipped", 0) > 0 -> "blocked"
      Map.get(counts, "cancelled", 0) == total and total > 0 -> "cancelled"
      true -> "passed"
    end
  end

  defp duration_ms(nil, _), do: nil
  defp duration_ms(_, nil), do: nil

  defp duration_ms(started_at, finished_at) do
    DateTime.diff(finished_at, started_at, :millisecond)
  end

  defp latency_ms(nil, _), do: nil

  defp latency_ms(finished_at, reported_at) do
    DateTime.diff(reported_at, finished_at, :millisecond)
  end

  defp report_dir do
    config = Application.get_env(:nixstasis, :e2e, [])
    raw = Keyword.get(config, :report_dir, "priv/e2e/reports")
    expand_path(raw)
  end

  defp expand_path(path) do
    case Path.type(path) do
      :absolute -> path
      :relative -> Path.expand(path, File.cwd!())
    end
  end

  def to_row(%RunResult{} = result) do
    %{
      journey_id: result.journey_id,
      status: result.status,
      failure_step: result.failure_step,
      failure_reason: result.failure_reason,
      duration_ms: result.duration_ms
    }
  end
end
