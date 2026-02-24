defmodule Nixstasis.TestSupport.ReportAssertions do
  @moduledoc false

  import ExUnit.Assertions

  def assert_ordered_by(rows, key, :asc) do
    values = Enum.map(rows, &Map.get(&1, key))
    assert values == Enum.sort(values)
  end

  def assert_ordered_by(rows, key, :desc) do
    values = Enum.map(rows, &Map.get(&1, key))
    assert values == Enum.sort(values, :desc)
  end
end
