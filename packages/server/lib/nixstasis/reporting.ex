defmodule Nixstasis.Reporting do
  @moduledoc """
  The Reporting context.
  """

  import Ecto.Query, only: [from: 2]

  alias Nixstasis.Domain
  alias Nixstasis.Repo
  alias Nixstasis.Reporting.CustomReport
  alias Nixstasis.Reporting.TableFilters

  def list_custom_reports do
    Domain.list_custom_reports!()
  end

  def list_custom_reports_with_view(opts \\ %{}) do
    reports =
      list_custom_reports()
      |> Enum.reject(&e2e_report?/1)
      |> Enum.map(&with_report_view_data/1)

    %{
      name_query: name_query,
      field_query: field_query,
      field_queries: field_queries,
      filters: filters,
      sort_by: sort_by,
      sort_dir: sort_dir
    } = list_view_opts(opts)

    reports
    |> filter_by_name(name_query)
    |> filter_by_field_query(field_query)
    |> filter_by_field_queries(field_queries)
    |> TableFilters.filter_rows(filters)
    |> TableFilters.sort_rows(sort_by, sort_dir)
  end

  defp list_view_opts(opts) do
    normalized_opts = normalize_option_keys(opts)

    %{
      name_query: Map.get(normalized_opts, "name_query", ""),
      field_query: Map.get(normalized_opts, "field_query", ""),
      field_queries: Map.get(normalized_opts, "field_queries", []),
      filters: Map.get(normalized_opts, "filters", []),
      sort_by: Map.get(normalized_opts, "sort_by"),
      sort_dir: Map.get(normalized_opts, "sort_dir", "asc")
    }
  end

  defp normalize_option_keys(opts) when is_map(opts) do
    Enum.reduce(opts, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_option_keys(_), do: %{}

  def get_custom_report!(id), do: Domain.get_custom_report!(id)

  def create_custom_report(attrs \\ %{}) do
    Domain.create_custom_report(attrs)
  end

  def custom_report_name_taken?(name) when is_binary(name) and name != "" do
    normalized_name = String.trim(name)

    if normalized_name == "" do
      false
    else
      query =
        from(r in "custom_reports",
          where: fragment("lower(?) = lower(?)", r.name, ^normalized_name),
          select: 1,
          limit: 1
        )

      Repo.one(query) == 1
    end
  end

  def custom_report_name_taken?(_), do: false

  def update_custom_report(%CustomReport{} = report, attrs) do
    Domain.update_custom_report(report, attrs)
  end

  def delete_custom_report(%CustomReport{} = report) do
    Domain.destroy_custom_report(report)
  end

  def save_view_preferences(scope, key, preferences) when is_binary(scope) and is_binary(key) do
    ensure_preference_table!()
    :ets.insert(:report_view_preferences, {{scope, key}, preferences})
    :ok
  end

  def load_view_preferences(scope, key) when is_binary(scope) and is_binary(key) do
    ensure_preference_table!()

    case :ets.lookup(:report_view_preferences, {scope, key}) do
      [{{^scope, ^key}, preferences}] -> preferences
      _ -> %{}
    end
  end

  def change_custom_report(report, attrs \\ %{})

  def change_custom_report(%CustomReport{id: nil}, attrs) do
    CustomReport
    |> AshPhoenix.Form.for_create(:create, domain: Domain, params: attrs)
  end

  def change_custom_report(%CustomReport{} = report, attrs) do
    report
    |> AshPhoenix.Form.for_update(:update, domain: Domain, params: attrs)
  end

  defp with_report_view_data(report) do
    fields = (report.config["fields"] || report.config[:fields] || []) |> Enum.filter(&is_map/1)

    field_tokens =
      fields
      |> Enum.flat_map(fn field ->
        [field["path"] || field[:path], field["alias"] || field[:alias]]
      end)
      |> Enum.filter(&is_binary/1)
      |> Enum.map_join(" ", &String.downcase/1)

    field_labels =
      fields
      |> Enum.map(fn field -> field["alias"] || field[:alias] || field["path"] || field[:path] end)
      |> Enum.filter(&is_binary/1)

    %{
      "id" => report.id,
      "name" => report.name,
      "field_tokens" => field_tokens,
      "field_labels" => field_labels,
      "field_paths" =>
        fields
        |> Enum.map(fn field -> field["path"] || field[:path] end)
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.downcase/1),
      "updated_at" => report.updated_at,
      "report" => report
    }
  end

  defp filter_by_name(reports, query) when query in [nil, ""], do: reports

  defp filter_by_name(reports, query) do
    q = String.downcase(String.trim(query))
    Enum.filter(reports, fn row -> String.contains?(String.downcase(row["name"] || ""), q) end)
  end

  defp filter_by_field_query(reports, query) when query in [nil, ""], do: reports

  defp filter_by_field_query(reports, query) do
    q = String.downcase(String.trim(query))
    Enum.filter(reports, fn row -> String.contains?(row["field_tokens"] || "", q) end)
  end

  defp filter_by_field_queries(reports, queries) when not is_list(queries), do: reports

  defp filter_by_field_queries(reports, queries) do
    normalized =
      queries
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase(String.trim(&1)))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if normalized == [] do
      reports
    else
      Enum.filter(reports, fn row ->
        field_paths = Map.get(row, "field_paths", [])
        Enum.all?(normalized, &(&1 in field_paths))
      end)
    end
  end

  defp e2e_report?(report) do
    source = report.config["source"] || report.config[:source]
    source == "e2e"
  end

  defp ensure_preference_table! do
    case :ets.whereis(:report_view_preferences) do
      :undefined ->
        :ets.new(:report_view_preferences, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        :ok
    end
  end
end
