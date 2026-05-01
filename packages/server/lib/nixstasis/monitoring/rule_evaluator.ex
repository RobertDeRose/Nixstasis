defmodule Nixstasis.Monitoring.RuleEvaluator do
  @moduledoc """
  Evaluates telemetry data against alert rules.
  """

  def evaluate(telemetry_payload, rule) do
    value = get_in_path(telemetry_payload, rule.condition_field)

    case value do
      nil -> false
      _ -> compare(value, rule.operator, rule.threshold_value)
    end
  end

  defp get_in_path(payload, path) do
    keys = String.split(path, ".")
    get_in(payload, keys)
  end

  defp compare(value, operator, threshold) when is_binary(threshold) do
    case cast_threshold(value, threshold) do
      {:ok, casted_threshold} -> do_compare(value, operator, casted_threshold)
      # Fallback to string comparison
      :error -> do_compare(value, operator, threshold)
    end
  end

  defp compare(value, operator, threshold), do: do_compare(value, operator, threshold)

  defp cast_threshold(val, threshold) when is_number(val) do
    case Float.parse(threshold) do
      {num, _} -> {:ok, num}
      :error -> :error
    end
  end

  defp cast_threshold(_val, threshold), do: {:ok, threshold}

  defp do_compare(val, ">", threshold), do: val > threshold
  defp do_compare(val, "<", threshold), do: val < threshold
  defp do_compare(val, "=", threshold), do: val == threshold
  # Just in case
  defp do_compare(val, "==", threshold), do: val == threshold
  defp do_compare(val, "is", threshold), do: to_string(val) == to_string(threshold)
  defp do_compare(val, "is not", threshold), do: to_string(val) != to_string(threshold)
  defp do_compare(val, "contains", threshold), do: String.contains?(to_string(val), to_string(threshold))
  defp do_compare(val, "doesn't contain", threshold), do: not String.contains?(to_string(val), to_string(threshold))
  defp do_compare(val, "!=", threshold), do: val != threshold
  defp do_compare(val, ">=", threshold), do: val >= threshold
  defp do_compare(val, "<=", threshold), do: val <= threshold
  defp do_compare(_, _, _), do: false
end
