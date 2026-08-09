defmodule Nixstasis.Reporting do
  @moduledoc """
  The Reporting context.
  """

  import Ecto.Query, only: [from: 2]
  require Ecto.Query

  alias Nixstasis.Domain
  alias Nixstasis.Repo
  alias Nixstasis.Reporting.CustomReport
  alias Nixstasis.Reporting.QueryBuilder

  @preference_scope_keys ["kind", "owner", "operator_id", "report_preference_scope"]
  @report_index_page_size 50
  @report_field_summary_limit 25
  @report_field_text_limit 128

  def list_custom_reports do
    Domain.list_custom_reports!()
  end

  def list_custom_reports_with_view(opts \\ %{}) do
    view_opts = list_view_opts(opts)

    page_offset = (view_opts.page - 1) * @report_index_page_size
    page_size = @report_index_page_size

    view_opts
    |> report_index_query()
    |> Ecto.Query.offset(^page_offset)
    |> Ecto.Query.limit(^page_size)
    |> Repo.all()
    |> Enum.map(&with_report_view_data/1)
  end

  def count_custom_reports_with_view(opts \\ %{}) do
    opts
    |> list_view_opts()
    |> report_index_query()
    |> Repo.aggregate(:count, :id)
  end

  defp report_index_query(view_opts) do
    "custom_reports"
    |> base_report_index_query()
    |> reject_e2e_reports()
    |> filter_report_names(view_opts.name_query)
    |> filter_report_field_query(view_opts.field_query)
    |> filter_report_field_queries(view_opts.field_queries)
    |> sort_report_index(view_opts.sort_by, view_opts.sort_dir)
  end

  defp list_view_opts(opts) do
    normalized_opts = normalize_option_keys(opts)

    %{
      name_query: Map.get(normalized_opts, "name_query", ""),
      field_query: Map.get(normalized_opts, "field_query", ""),
      field_queries: Map.get(normalized_opts, "field_queries", []),
      sort_by: Map.get(normalized_opts, "sort_by"),
      sort_dir: Map.get(normalized_opts, "sort_dir", "asc"),
      page: normalize_page(Map.get(normalized_opts, "page", 1))
    }
  end

  defp normalize_page(page) when is_integer(page) and page > 0, do: page

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp normalize_page(_), do: 1

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

  def report_fields(%CustomReport{} = report) do
    QueryBuilder.fields_for_report(report.config)
  end

  def run_custom_report(%CustomReport{} = report, opts \\ %{}) do
    report.config
    |> QueryBuilder.build(opts)
    |> Repo.all()
  end

  def preference_scope(%{"report_preferences" => scope_attrs}) when is_map(scope_attrs) do
    preference_scope(scope_attrs)
  end

  def preference_scope(scope_attrs) when is_map(scope_attrs) do
    normalized_attrs = normalize_option_keys(scope_attrs)
    explicit_preference_scope(normalized_attrs)
  end

  def preference_scope(_), do: nil

  defp explicit_preference_scope(scope_attrs) do
    normalized_scope = Map.take(scope_attrs, @preference_scope_keys)
    kind = normalize_preference_scope_value(Map.get(normalized_scope, "kind"))
    owner = normalize_preference_scope_value(Map.get(normalized_scope, "owner"))
    operator_id = normalize_preference_scope_value(Map.get(normalized_scope, "operator_id"))
    named_scope = normalize_preference_scope_value(Map.get(normalized_scope, "report_preference_scope"))

    cond do
      owner != "" -> format_preference_scope(kind, "owner", owner)
      operator_id != "" -> format_preference_scope(kind, "operator", operator_id)
      named_scope != "" -> format_preference_scope(kind, "scope", named_scope)
      true -> nil
    end
  end

  defp format_preference_scope("", owner_key, owner_value) do
    format_preference_scope("report_live", owner_key, owner_value)
  end

  defp format_preference_scope(kind, owner_key, owner_value), do: "kind=#{kind};#{owner_key}=#{owner_value}"

  def save_view_preferences(nil, _key, _preferences), do: :ok

  def save_view_preferences(scope, key, preferences) when is_binary(scope) and is_binary(key) and is_map(preferences) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert_all(
      "report_view_preferences",
      [
        %{
          scope: scope,
          view_key: key,
          preferences: preferences,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:preferences, :updated_at]},
      conflict_target: [:scope, :view_key]
    )

    :ok
  end

  def load_view_preferences(nil, _key), do: %{}

  def load_view_preferences(scope, key) when is_binary(scope) and is_binary(key) do
    query =
      from(p in "report_view_preferences",
        where: p.scope == ^scope and p.view_key == ^key,
        select: p.preferences,
        limit: 1
      )

    case Repo.one(query) do
      preferences when is_map(preferences) -> preferences
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

  defp base_report_index_query(source) do
    from(r in source,
      select: %{
        id: r.id,
        name: r.name,
        field_summaries:
          fragment(
            """
            (
              select coalesce(
                jsonb_agg(
                  jsonb_build_object(
                    'path', left(coalesce(field->>'path', ''), ?),
                    'alias', left(coalesce(field->>'alias', field->>'path', ''), ?)
                  )
                ),
                '[]'::jsonb
              )
              from (
                select field
                from jsonb_array_elements(
                  case
                    when jsonb_typeof(?->'fields') = 'array' then ?->'fields'
                    else '[]'::jsonb
                  end
                ) as field
                where jsonb_typeof(field) = 'object'
                limit ?
              ) as bounded_fields
            )
            """,
            ^@report_field_text_limit,
            ^@report_field_text_limit,
            r.config,
            r.config,
            ^@report_field_summary_limit
          ),
        column_count:
          fragment(
            "case when jsonb_typeof(?->'fields') = 'array' then jsonb_array_length(?->'fields') else 0 end",
            r.config,
            r.config
          ),
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    )
  end

  defp report_index_summary_fields(report) do
    case report.field_summaries do
      summaries when is_list(summaries) ->
        summaries
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn field ->
          %{
            "path" => field["path"] || "",
            "alias" => field["alias"] || field["path"] || ""
          }
        end)

      _ ->
        []
    end
  end

  defp with_report_view_data(report) do
    fields = report_index_summary_fields(report)
    field_tokens = fields |> Enum.flat_map(&[&1["path"], &1["alias"]]) |> Enum.join(" ") |> String.downcase()
    field_labels = Enum.map(fields, & &1["alias"])
    field_paths = fields |> Enum.map(& &1["path"]) |> Enum.reject(&(&1 == "")) |> Enum.map(&String.downcase/1)

    %{
      "id" => report.id,
      "name" => report.name,
      "field_tokens" => field_tokens,
      "field_labels" => field_labels,
      "field_paths" => field_paths,
      "column_count" => report.column_count,
      "updated_at" => report.updated_at
    }
  end

  defp reject_e2e_reports(query) do
    from(r in query, where: fragment("coalesce(?->>'source', 'telemetry') <> 'e2e'", r.config))
  end

  defp filter_report_names(query, name_query) when name_query in [nil, ""], do: query

  defp filter_report_names(query, name_query) do
    pattern = "%#{String.downcase(String.trim(name_query))}%"
    from(r in query, where: fragment("lower(?) like ?", r.name, ^pattern))
  end

  defp filter_report_field_query(query, field_query) when field_query in [nil, ""], do: query

  defp filter_report_field_query(query, field_query) do
    pattern = "%#{String.downcase(String.trim(field_query))}%"

    from(r in query,
      where:
        fragment(
          """
          exists (
            select 1
            from jsonb_array_elements(
              case
                when jsonb_typeof(?->'fields') = 'array' then ?->'fields'
                else '[]'::jsonb
              end
            ) as field
            where lower(coalesce(field->>'path', '') || ' ' || coalesce(field->>'alias', '')) like ?
          )
          """,
          r.config,
          r.config,
          ^pattern
        )
    )
  end

  defp filter_report_field_queries(query, queries) when not is_list(queries), do: query

  defp filter_report_field_queries(query, queries) do
    queries
    |> normalize_field_queries()
    |> Enum.reduce(query, fn field_path, acc ->
      from(r in acc,
        where:
          fragment(
            """
            exists (
              select 1
              from jsonb_array_elements(
                case
                  when jsonb_typeof(?->'fields') = 'array' then ?->'fields'
                  else '[]'::jsonb
                end
              ) as field
              where lower(coalesce(field->>'path', '')) = ?
            )
            """,
            r.config,
            r.config,
            ^field_path
          )
      )
    end)
  end

  defp sort_report_index(query, "name", "desc"),
    do: from(r in query, order_by: [desc: fragment("lower(?)", r.name), asc: r.id])

  defp sort_report_index(query, "name", _),
    do: from(r in query, order_by: [asc: fragment("lower(?)", r.name), asc: r.id])

  defp sort_report_index(query, _, _), do: sort_report_index(query, "name", "asc")

  defp normalize_field_queries(queries) do
    queries
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase(String.trim(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_preference_scope_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_preference_scope_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_preference_scope_value(nil), do: ""
  defp normalize_preference_scope_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_preference_scope_value(_), do: ""
end
