defmodule NixstasisWeb.E2ERunResultJSON do
  alias Nixstasis.E2E.RunResult

  def index(%{results: results}) do
    %{data: Enum.map(results, &data/1)}
  end

  defp data(%RunResult{} = result) do
    %{
      id: result.id,
      journey_id: result.journey_id,
      status: result.status,
      failure_step: result.failure_step,
      failure_reason: result.failure_reason,
      log_ref: result.log_ref,
      started_at: result.started_at,
      finished_at: result.finished_at,
      duration_ms: result.duration_ms
    }
  end
end
