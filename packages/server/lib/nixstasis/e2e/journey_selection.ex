defmodule Nixstasis.E2E.JourneySelection do
  @moduledoc """
  Validates journey selections against configured suites.
  """

  def resolve(suite_id, journey_ids) when is_binary(suite_id) do
    suites = suites()

    case Map.fetch(suites, suite_id) do
      {:ok, suite_journeys} ->
        selected = normalize_journeys(journey_ids, suite_journeys)

        case validate_subset(selected, suite_journeys) do
          :ok -> {:ok, selected}
          {:error, message} -> {:error, message}
        end

      :error ->
        {:error, "Unknown suite '#{suite_id}'."}
    end
  end

  def resolve(_, _), do: {:error, "Suite ID must be provided."}

  defp normalize_journeys(nil, suite_journeys), do: suite_journeys
  defp normalize_journeys([], suite_journeys), do: suite_journeys
  defp normalize_journeys(journeys, _suite_journeys) when is_list(journeys), do: journeys
  defp normalize_journeys(_, suite_journeys), do: suite_journeys

  defp validate_subset(selected, suite_journeys) do
    invalid = selected -- suite_journeys

    if invalid == [] do
      if selected == [] do
        {:error, "At least one journey must be selected."}
      else
        :ok
      end
    else
      {:error, "Invalid journeys selected: #{Enum.join(invalid, ", ")}."}
    end
  end

  defp suites do
    Application.get_env(:nixstasis, :e2e, [])
    |> Keyword.get(:suites, %{})
  end
end
