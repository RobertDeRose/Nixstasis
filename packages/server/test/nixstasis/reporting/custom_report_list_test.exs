defmodule Nixstasis.Reporting.CustomReportListTest do
  use Nixstasis.DataCase, async: true

  alias Nixstasis.Reporting

  test "sorts and filters custom reports for index view" do
    {:ok, _} =
      Reporting.create_custom_report(%{
        "name" => "Bravo",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
      })

    {:ok, _} =
      Reporting.create_custom_report(%{
        "name" => "Alpha",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "temp"}, %{"path" => "humidity"}],
          "filters" => []
        }
      })

    {:ok, _} =
      Reporting.create_custom_report(%{
        "name" => "Hidden E2E",
        "config" => %{"source" => "e2e", "fields" => [%{"path" => "status"}], "filters" => []}
      })

    rows =
      Reporting.list_custom_reports_with_view(%{
        "sort_by" => "name",
        "sort_dir" => "asc",
        "name_query" => "a"
      })

    assert ["Alpha", "Bravo"] == Enum.map(rows, & &1["name"])
    refute Enum.any?(rows, &(&1["name"] == "Hidden E2E"))
    assert Enum.all?(rows, &(&1["column_count"] > 0))
  end
end
