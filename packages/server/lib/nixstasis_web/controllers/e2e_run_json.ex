defmodule NixstasisWeb.E2ERunJSON do
  alias Nixstasis.E2E.Run

  def index(%{runs: runs}) do
    %{data: Enum.map(runs, &data/1)}
  end

  def show(%{run: run}) do
    %{data: data(run)}
  end

  def suites(%{suites: suites}) do
    %{
      data:
        Enum.map(suites, fn suite ->
          %{
            id: suite.id,
            journey_ids: suite.journey_ids
          }
        end)
    }
  end

  defp data(%Run{} = run) do
    %{
      id: run.id,
      suite_id: run.suite_id,
      journey_ids: run.journey_ids,
      environment_label: run.environment_label,
      trigger_source: run.trigger_source,
      protocol_version: run.protocol_version,
      status: run.status,
      started_at: run.started_at,
      finished_at: run.finished_at
    }
  end
end
