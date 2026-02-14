defmodule Nixstasis.E2E.Metrics do
  @moduledoc """
  Calculates aggregate E2E metrics.
  """

  alias Nixstasis.E2E.RunResult

  def flaky_rate(results) when is_list(results) do
    total = length(results)

    if total == 0 do
      0.0
    else
      flaky = Enum.count(results, &flaky?/1)
      flaky / total
    end
  end

  defp flaky?(%RunResult{status: status, failure_reason: reason}) do
    status == "failed" && contains_flaky?(reason)
  end

  defp flaky?(_), do: false

  defp contains_flaky?(nil), do: false

  defp contains_flaky?(reason) do
    reason
    |> String.downcase()
    |> String.contains?("flaky")
  end
end
