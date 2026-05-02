defmodule Nixstasis.Reporting.TableFiltersTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Reporting.TableFilters

  test "supports gt/gte/eq/lte/lt operators with numeric coercion" do
    rows = [
      %{"temp" => "10"},
      %{"temp" => 20},
      %{"temp" => "30"}
    ]

    assert [%{"temp" => "30"}] =
             TableFilters.filter_rows(rows, [%{"column" => "temp", "operator" => ">", "value" => 25}])

    assert 2 == TableFilters.filter_rows(rows, [%{"column" => "temp", "operator" => ">=", "value" => 20}]) |> length()

    assert [%{"temp" => 20}] =
             TableFilters.filter_rows(rows, [%{"column" => "temp", "operator" => "==", "value" => "20"}])

    assert 2 == TableFilters.filter_rows(rows, [%{"column" => "temp", "operator" => "<=", "value" => 20}]) |> length()

    assert [%{"temp" => "10"}] =
             TableFilters.filter_rows(rows, [%{"column" => "temp", "operator" => "<", "value" => 20}])
  end

  test "treats blank filter values as no-op and sorts values" do
    rows = [%{"name" => "Zulu"}, %{"name" => "alpha"}, %{"name" => "Beta"}]

    assert rows == TableFilters.filter_rows(rows, [%{"column" => "name", "operator" => "==", "value" => ""}])

    assert ["alpha", "Beta", "Zulu"] ==
             rows
             |> TableFilters.sort_rows("name", "asc")
             |> Enum.map(& &1["name"])

    assert ["Zulu", "Beta", "alpha"] ==
             rows
             |> TableFilters.sort_rows("name", "desc")
             |> Enum.map(& &1["name"])
  end

  test "supports string operators contains/doesn't contain/is/is not" do
    rows = [%{"status" => "ok"}, %{"status" => "warning"}, %{"status" => "error"}]

    assert [%{"status" => "warning"}] =
             TableFilters.filter_rows(rows, [%{"column" => "status", "operator" => "is", "value" => "warning"}])

    assert 2 ==
             rows
             |> TableFilters.filter_rows([
               %{"column" => "status", "operator" => "is not", "value" => "warning"}
             ])
             |> length()

    assert 2 ==
             rows
             |> TableFilters.filter_rows([
               %{"column" => "status", "operator" => "contains", "value" => "or,ok"}
             ])
             |> length()

    assert [%{"status" => "warning"}] =
             TableFilters.filter_rows(rows, [
               %{"column" => "status", "operator" => "doesn't contain", "value" => "or,ok"}
             ])
  end
end
