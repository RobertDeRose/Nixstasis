defmodule Nixstasis.Reporting.TableFilters do
  @moduledoc """
  Shared filtering and sorting helpers for report list and result-table views.
  """

  @type operator :: :gt | :gte | :eq | :lte | :lt | :contains | :not_contains | :neq

  @spec filter_rows(list(map()), list(map())) :: list(map())
  def filter_rows(rows, filters) when is_list(rows) and is_list(filters) do
    Enum.filter(rows, fn row ->
      Enum.all?(filters, &matches_filter?(row, &1))
    end)
  end

  @spec sort_rows(list(map()), nil | String.t(), nil | String.t()) :: list(map())
  def sort_rows(rows, nil, _dir), do: rows
  def sort_rows(rows, "", _dir), do: rows

  def sort_rows(rows, sort_by, sort_dir) when is_list(rows) do
    direction = if sort_dir in ["desc", :desc], do: :desc, else: :asc

    Enum.sort_by(
      rows,
      fn row -> normalize_sort_value(value_for(row, sort_by)) end,
      fn left, right ->
        case direction do
          :asc -> left <= right
          :desc -> left >= right
        end
      end
    )
  end

  @spec report_column_count(map()) :: non_neg_integer()
  def report_column_count(report) do
    config = value_for(report, "config") || %{}
    fields = value_for(config, "fields") || []
    length(fields)
  end

  defp matches_filter?(_row, %{"value" => value}) when value in [nil, ""], do: true
  defp matches_filter?(_row, %{value: value}) when value in [nil, ""], do: true

  defp matches_filter?(row, filter) do
    key =
      filter["column"] || filter[:column] || filter["field"] || filter[:field] || filter["path"] ||
        filter[:path]

    operator = normalize_operator(filter["operator"] || filter[:operator])
    expected = filter["value"] || filter[:value]
    actual = value_for(row, key)

    compare(operator, actual, expected)
  end

  defp normalize_operator("gt"), do: :gt
  defp normalize_operator(">"), do: :gt
  defp normalize_operator("gte"), do: :gte
  defp normalize_operator(">="), do: :gte
  defp normalize_operator("eq"), do: :eq
  defp normalize_operator("=="), do: :eq
  defp normalize_operator("="), do: :eq
  defp normalize_operator("is"), do: :eq
  defp normalize_operator("is not"), do: :neq
  defp normalize_operator("lte"), do: :lte
  defp normalize_operator("<="), do: :lte
  defp normalize_operator("lt"), do: :lt
  defp normalize_operator("<"), do: :lt
  defp normalize_operator("contains"), do: :contains
  defp normalize_operator("doesn't contain"), do: :not_contains
  defp normalize_operator("doesnt contain"), do: :not_contains
  defp normalize_operator("in"), do: :contains
  defp normalize_operator("not in"), do: :not_contains
  defp normalize_operator(_), do: :eq

  defp compare(:eq, actual, expected) do
    to_string_safe(actual) == to_string_safe(expected)
  end

  defp compare(:neq, actual, expected) do
    to_string_safe(actual) != to_string_safe(expected)
  end

  defp compare(:contains, actual, expected) do
    actual_string = actual |> to_string_safe() |> String.downcase()

    needles =
      expected
      |> to_string_safe()
      |> String.split(",", trim: true)
      |> Enum.map(&String.downcase(String.trim(&1)))
      |> Enum.reject(&(&1 == ""))

    Enum.any?(needles, &String.contains?(actual_string, &1))
  end

  defp compare(:not_contains, actual, expected), do: not compare(:contains, actual, expected)

  defp compare(operator, actual, expected) do
    case comparable_pair(actual, expected) do
      {:number, left, right} ->
        do_compare(operator, left, right)

      {:string, left, right} ->
        do_compare(operator, left, right)
    end
  end

  defp do_compare(:gt, left, right), do: left > right
  defp do_compare(:gte, left, right), do: left >= right
  defp do_compare(:eq, left, right), do: left == right
  defp do_compare(:lte, left, right), do: left <= right
  defp do_compare(:lt, left, right), do: left < right

  defp comparable_pair(actual, expected) do
    actual_str = to_string_safe(actual)
    expected_str = to_string_safe(expected)

    case {parse_number(actual_str), parse_number(expected_str)} do
      {{:ok, left}, {:ok, right}} -> {:number, left, right}
      _ -> {:string, String.downcase(actual_str), String.downcase(expected_str)}
    end
  end

  defp parse_number(value) when is_binary(value) do
    value = String.trim(value)

    case Float.parse(value) do
      {num, ""} -> {:ok, num}
      _ -> :error
    end
  end

  defp parse_number(_), do: :error

  defp normalize_sort_value(nil), do: ""

  defp normalize_sort_value(value) when is_binary(value) do
    case parse_number(value) do
      {:ok, number} -> number
      :error -> String.downcase(value)
    end
  end

  defp normalize_sort_value(value) when is_number(value), do: value
  defp normalize_sort_value(value), do: to_string_safe(value)

  defp value_for(nil, _key), do: nil
  defp value_for(_row, nil), do: nil

  defp value_for(row, key) when is_atom(key), do: value_for(row, Atom.to_string(key))

  defp value_for(row, key) do
    if is_map(row) do
      Map.get(row, key) || Map.get(row, String.to_atom(key))
    else
      nil
    end
  rescue
    ArgumentError -> Map.get(row, key)
  end

  defp to_string_safe(nil), do: ""
  defp to_string_safe(value) when is_binary(value), do: value
  defp to_string_safe(value), do: to_string(value)
end
