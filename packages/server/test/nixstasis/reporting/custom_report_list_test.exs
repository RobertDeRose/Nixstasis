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

  test "paginates report summaries and counts rows without loading full config" do
    for index <- 1..55 do
      {:ok, _} =
        Reporting.create_custom_report(%{
          "name" => "Paged #{String.pad_leading(Integer.to_string(index), 2, "0")}",
          "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
        })
    end

    assert Reporting.count_custom_reports_with_view(%{"name_query" => "Paged"}) == 55
    first_page = Reporting.list_custom_reports_with_view(%{"name_query" => "Paged", "page" => 1})
    second_page = Reporting.list_custom_reports_with_view(%{"name_query" => "Paged", "page" => 2})
    empty_page = Reporting.list_custom_reports_with_view(%{"name_query" => "Paged", "page" => 3})

    assert length(first_page) == 50
    assert Enum.at(first_page, 0)["name"] == "Paged 01"
    assert length(second_page) == 5
    assert Enum.map(second_page, & &1["name"]) == ["Paged 51", "Paged 52", "Paged 53", "Paged 54", "Paged 55"]
    assert empty_page == []
  end

  test "report summaries cap field labels and label lengths" do
    fields = for index <- 1..30, do: %{"path" => String.duplicate("p", 200) <> Integer.to_string(index)}

    {:ok, _report} =
      Reporting.create_custom_report(%{
        "name" => "Bounded Summary",
        "config" => %{"source" => "telemetry", "fields" => fields, "filters" => []}
      })

    [summary] = Reporting.list_custom_reports_with_view(%{"name_query" => "Bounded Summary"})
    assert length(summary["field_labels"]) == 25
    assert Enum.all?(summary["field_labels"], &(String.length(&1) <= 128))
  end

  test "paginates similarly named reports with stable ID ordering" do
    for index <- 1..51 do
      {:ok, _} =
        Reporting.create_custom_report(%{
          "name" => "Collision #{String.pad_leading(Integer.to_string(index), 2, "0")}",
          "config" => %{"source" => "telemetry", "fields" => [], "filters" => []}
        })
    end

    page_one = Reporting.list_custom_reports_with_view(%{"page" => 1})
    page_two = Reporting.list_custom_reports_with_view(%{"page" => 2})
    repeated_page_one = Reporting.list_custom_reports_with_view(%{"page" => 1})

    assert length(page_one) == 50
    assert length(page_two) == 1
    assert Enum.map(page_one, & &1["id"]) == Enum.map(repeated_page_one, & &1["id"])
    assert MapSet.disjoint?(MapSet.new(Enum.map(page_one, & &1["id"])), MapSet.new(Enum.map(page_two, & &1["id"])))
  end
end
