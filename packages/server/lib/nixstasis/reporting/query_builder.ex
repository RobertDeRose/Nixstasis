defmodule Nixstasis.Reporting.QueryBuilder do
  @moduledoc """
  Builds dynamic report queries from configuration.
  """

  import Ecto.Query

  alias Nixstasis.Domain
  alias Nixstasis.E2E.Run
  alias Nixstasis.Monitoring.Telemetry
  alias Nixstasis.Reporting.TableFilters

  @telemetry_fields ~w(id device_id timestamp inserted_at updated_at)a
  @e2e_fields ~w(id suite_id journey_ids environment_label trigger_source protocol_version status started_at finished_at inserted_at updated_at)a

  @telemetry_field_lookup Map.new(@telemetry_fields, &{Atom.to_string(&1), &1})
  @e2e_field_lookup Map.new(@e2e_fields, &{Atom.to_string(&1), &1})
  @max_in_memory_rows 250

  @e2e_default_fields [
    %{"path" => "id", "alias" => "run_id"},
    %{"path" => "suite_id", "alias" => "suite"},
    %{"path" => "environment_label", "alias" => "environment"},
    %{"path" => "status", "alias" => "status"},
    %{"path" => "started_at", "alias" => "started_at"},
    %{"path" => "finished_at", "alias" => "finished_at"}
  ]

  def build(config, opts \\ %{}) do
    source = normalize_source(config["source"] || config[:source])
    fields = fields_for_report(config)
    filters = (config["filters"] || config[:filters] || []) ++ query_filters_for_result_view(opts, fields)
    sort_by = opts[:sort_by] || opts["sort_by"]
    sort_dir = opts[:sort_dir] || opts["sort_dir"] || "asc"
    numeric_sort? = telemetry_numeric_sort?(source, sort_by, filters, opts)

    source
    |> base_query()
    |> apply_schema_scope(config, source)
    |> apply_filters(filters, source)
    |> apply_result_sort(sort_by, sort_dir, fields, source, numeric_sort?)
    |> apply_non_empty_result_fields(fields, source)
    |> apply_result_pagination(opts)
    |> select_fields(fields, source)
  end

  def fields_for_report(config) do
    source = normalize_source(config["source"] || config[:source])
    fields = config["fields"] || config[:fields] || []

    case {source, fields} do
      {"e2e", []} -> @e2e_default_fields
      _ -> fields
    end
  end

  defp apply_non_empty_result_fields(query, fields, "telemetry") do
    paths =
      fields
      |> Enum.map(&(&1["path"] || &1[:path]))
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    case paths do
      [] ->
        query

      paths ->
        condition =
          Enum.reduce(paths, dynamic(false), fn path, condition ->
            segments = String.split(path, ".", trim: true)

            dynamic(
              [q],
              ^condition or fragment("NULLIF(? #>> ?, '') IS NOT NULL", q.payload, ^segments)
            )
          end)

        from(q in query, where: ^condition)
    end
  end

  defp apply_non_empty_result_fields(query, _fields, _source), do: query

  def apply_result_view(rows, opts \\ %{}) when is_list(rows) do
    sort_by = opts[:sort_by] || opts["sort_by"]
    sort_dir = opts[:sort_dir] || opts["sort_dir"] || "asc"
    filters = opts[:filters] || opts["filters"] || []

    rows
    |> Enum.take(@max_in_memory_rows)
    |> TableFilters.filter_rows(filters)
    |> TableFilters.sort_rows(sort_by, sort_dir)
  end

  def max_in_memory_rows, do: @max_in_memory_rows

  defp normalize_source(nil), do: "telemetry"
  defp normalize_source(source) when is_atom(source), do: Atom.to_string(source)
  defp normalize_source(source) when is_binary(source), do: source
  defp normalize_source(_), do: "telemetry"

  defp base_query("telemetry") do
    Telemetry
    |> AshPostgres.DataLayer.resource_to_query(Domain)
    |> then(fn query -> from(t in query) end)
  end

  defp base_query("e2e"), do: from(r in Run)

  defp base_query(_unknown), do: from(r in Run, where: false)

  defp apply_schema_scope(query, config, "telemetry") do
    schema_id = config["schema_id"] || config[:schema_id]
    schema_version = config["schema_version"] || config[:schema_version]

    cond do
      present_scope_value?(schema_id) and present_scope_value?(schema_version) ->
        from(q in query,
          join: d in "devices",
          on: d.id == q.device_id,
          where: d.product_name == ^schema_id,
          where: fragment("COALESCE(NULLIF(?->>'version', ''), 'v1') = ?", d.schema, ^schema_version)
        )

      present_scope_value?(schema_id) ->
        from(q in query,
          join: d in "devices",
          on: d.id == q.device_id,
          where: d.product_name == ^schema_id
        )

      true ->
        query
    end
  end

  defp apply_schema_scope(query, _config, _source), do: query

  defp present_scope_value?(value), do: is_binary(value) and String.trim(value) != ""

  defp select_fields(query, fields, "telemetry") do
    select_map =
      Enum.reduce(fields, %{}, fn field, acc ->
        alias_name = normalize_alias(field["alias"] || field[:alias], field["path"] || field[:path])
        path = field["path"] || field[:path]

        if is_binary(alias_name) and is_binary(path) do
          Map.put(acc, alias_name, build_payload_selection(path))
        else
          acc
        end
      end)

    from(q in query, select: ^select_map)
  end

  defp select_fields(query, fields, "e2e") do
    select_map =
      Enum.reduce(fields, %{}, fn field, acc ->
        alias_name = normalize_alias(field["alias"] || field[:alias], field["path"] || field[:path])
        path = field["path"] || field[:path]

        case field_atom_for("e2e", path) do
          nil ->
            acc

          field_atom ->
            Map.put(acc, alias_name, dynamic([r], field(r, ^field_atom)))
        end
      end)

    from(q in query, select: ^select_map)
  end

  defp select_fields(query, fields, source) when source not in ["telemetry", "e2e"] do
    select_fields(query, fields, "telemetry")
  end

  defp normalize_alias(alias_name, _path) when is_binary(alias_name) and alias_name != "", do: alias_name
  defp normalize_alias(_, path) when is_binary(path), do: path
  defp normalize_alias(_, _), do: nil

  defp build_payload_selection(path) do
    if String.contains?(path, ".") do
      segments = String.split(path, ".", trim: true)
      dynamic([t], fragment("? #>> ?", t.payload, ^segments))
    else
      dynamic([t], fragment("?->?", t.payload, ^path))
    end
  end

  defp apply_filters(query, filters, source) do
    Enum.reduce(filters, query, fn filter, acc ->
      apply_filter(acc, filter, source)
    end)
  end

  defp query_filters_for_result_view(opts, fields) do
    opts
    |> then(fn opts -> opts[:filters] || opts["filters"] || [] end)
    |> Enum.filter(&pushdown_filter?/1)
    |> Enum.map(&result_view_filter(&1, fields))
  end

  defp result_view_filter(filter, fields) do
    configured_path = field_path_for_column(filter_target_name(filter), fields)

    %{
      "path" => configured_path || filter_path(filter),
      "field" => if(configured_path, do: nil, else: filter_value(filter, "field")),
      "operator" => filter_value(filter, "operator"),
      "value" => filter_value(filter, "value")
    }
  end

  defp field_path_for_column(column, fields) when is_binary(column) do
    fields
    |> Enum.find(fn field ->
      normalize_alias(field["alias"] || field[:alias], field["path"] || field[:path]) == column
    end)
    |> case do
      nil -> nil
      field -> field["path"] || field[:path]
    end
  end

  defp field_path_for_column(_column, _fields), do: nil

  @pushdown_operators [
    "=",
    "==",
    "is",
    "is not",
    "!=",
    ">",
    ">=",
    "<",
    "<=",
    "contains",
    "doesn't contain",
    "doesnt contain"
  ]

  defp pushdown_filter?(filter) do
    present?(filter_target_name(filter)) and
      present?(filter_value(filter, "value")) and
      filter_value(filter, "operator") in @pushdown_operators
  end

  defp filter_target_name(filter) do
    filter_value(filter, "path") || filter_value(filter, "column") || filter_value(filter, "field")
  end

  defp filter_path(filter), do: filter_value(filter, "path") || filter_value(filter, "column")
  defp filter_value(filter, key), do: filter[key] || filter[String.to_existing_atom(key)]
  defp present?(value), do: value not in [nil, ""]

  defp apply_filter(query, filter, source) do
    field = filter["field"] || filter[:field]
    path = filter["path"] || filter[:path]
    op = filter["operator"] || filter[:operator]
    val = filter["value"] || filter[:value]

    case filter_target(field, path, source) do
      {:schema, field_name} ->
        apply_schema_filter(query, source, field_name, op, val)

      {:json_path, json_path} ->
        apply_json_path_filter(query, json_path, op, val)

      :ignore ->
        query
    end
  end

  defp filter_target(field, _path, _source) when is_binary(field) and field != "" do
    {:schema, field}
  end

  defp filter_target(field, _path, source) when not is_nil(field) and source in ["telemetry", "e2e"] do
    {:schema, field}
  end

  defp filter_target(_field, path, "telemetry") when is_binary(path) and path != "" do
    {:json_path, path}
  end

  defp filter_target(_field, path, "e2e") when is_binary(path) and path != "" do
    {:schema, path}
  end

  defp filter_target(_field, path, "telemetry") when not is_nil(path), do: {:json_path, path}
  defp filter_target(_field, path, "e2e") when not is_nil(path), do: {:schema, path}
  defp filter_target(_field, _path, _source), do: :ignore

  defp apply_schema_filter(query, source, field_name, op, val) do
    case field_atom_for(source, field_name) do
      nil ->
        query

      field_atom ->
        apply_schema_operator(query, field_atom, op, val)
    end
  end

  defp apply_schema_operator(query, field_atom, "=", val),
    do: from(q in query, where: field(q, ^field_atom) == ^val)

  defp apply_schema_operator(query, field_atom, "==", val),
    do: from(q in query, where: field(q, ^field_atom) == ^val)

  defp apply_schema_operator(query, field_atom, "is", val),
    do: from(q in query, where: field(q, ^field_atom) == ^val)

  defp apply_schema_operator(query, field_atom, "!=", val),
    do: from(q in query, where: field(q, ^field_atom) != ^val)

  defp apply_schema_operator(query, field_atom, "is not", val),
    do: from(q in query, where: field(q, ^field_atom) != ^val)

  defp apply_schema_operator(query, field_atom, "contains", val),
    do: from(q in query, where: ilike(type(field(q, ^field_atom), :string), ^"%#{val}%"))

  defp apply_schema_operator(query, field_atom, "doesn't contain", val),
    do: from(q in query, where: not ilike(type(field(q, ^field_atom), :string), ^"%#{val}%"))

  defp apply_schema_operator(query, field_atom, "doesnt contain", val),
    do: from(q in query, where: not ilike(type(field(q, ^field_atom), :string), ^"%#{val}%"))

  defp apply_schema_operator(query, field_atom, ">", val),
    do: from(q in query, where: field(q, ^field_atom) > ^val)

  defp apply_schema_operator(query, field_atom, ">=", val),
    do: from(q in query, where: field(q, ^field_atom) >= ^val)

  defp apply_schema_operator(query, field_atom, "<", val),
    do: from(q in query, where: field(q, ^field_atom) < ^val)

  defp apply_schema_operator(query, field_atom, "<=", val),
    do: from(q in query, where: field(q, ^field_atom) <= ^val)

  defp apply_schema_operator(query, _field_atom, _op, _val), do: query

  defp field_atom_for(source, field_name) do
    normalized =
      cond do
        is_atom(field_name) -> Atom.to_string(field_name)
        is_binary(field_name) -> field_name
        true -> nil
      end

    lookup =
      case source do
        "telemetry" -> @telemetry_field_lookup
        "e2e" -> @e2e_field_lookup
        _ -> %{}
      end

    if is_binary(normalized), do: Map.get(lookup, normalized), else: nil
  end

  defp apply_json_path_filter(query, path, op, val) do
    normalized_op = normalize_query_operator(op)
    {filter_value, numeric?} = normalize_json_filter_value(normalized_op, val)

    if normalized_op in ["=", "!=", ">", ">=", "<", "<=", "contains", "not_contains"] do
      dynamic_filter(query, path, normalized_op, filter_value, numeric?)
    else
      query
    end
  end

  defp normalize_json_filter_value(op, val) when op in [">", ">=", "<", "<="] do
    case parse_number(val) do
      {:ok, number} -> {number, true}
      :error -> {val, false}
    end
  end

  defp normalize_json_filter_value(_op, val) do
    case val do
      value when is_integer(value) or is_float(value) -> {value, true}
      value -> {value, false}
    end
  end

  defp dynamic_filter(query, path, op, val, numeric?) do
    path_segments = String.split(path, ".", trim: true)

    if numeric? do
      dynamic_filter_numeric(query, path_segments, op, val)
    else
      dynamic_filter_text(query, path_segments, op, val)
    end
  end

  defp dynamic_filter_numeric(query, path_segments, "=", val),
    do: from(q in query, where: fragment("( ? #>> ? )::numeric = ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_numeric(query, path_segments, "!=", val),
    do: from(q in query, where: fragment("( ? #>> ? )::numeric != ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_numeric(query, path_segments, ">", val),
    do: from(q in query, where: fragment("( ? #>> ? )::numeric > ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_numeric(query, path_segments, ">=", val),
    do: from(q in query, where: fragment("( ? #>> ? )::numeric >= ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_numeric(query, path_segments, "<", val),
    do: from(q in query, where: fragment("( ? #>> ? )::numeric < ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_numeric(query, path_segments, "<=", val),
    do: from(q in query, where: fragment("( ? #>> ? )::numeric <= ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_numeric(query, _path_segments, _op, _val), do: query

  defp dynamic_filter_text(query, path_segments, "=", val),
    do: from(q in query, where: fragment("? #>> ? = ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_text(query, path_segments, "!=", val),
    do: from(q in query, where: fragment("? #>> ? != ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_text(query, path_segments, "contains", val),
    do: from(q in query, where: fragment("? #>> ? ilike ?", q.payload, ^path_segments, ^"%#{val}%"))

  defp dynamic_filter_text(query, path_segments, "not_contains", val),
    do: from(q in query, where: fragment("not (? #>> ? ilike ?)", q.payload, ^path_segments, ^"%#{val}%"))

  defp dynamic_filter_text(query, path_segments, ">", val),
    do: from(q in query, where: fragment("? #>> ? > ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_text(query, path_segments, ">=", val),
    do: from(q in query, where: fragment("? #>> ? >= ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_text(query, path_segments, "<", val),
    do: from(q in query, where: fragment("? #>> ? < ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_text(query, path_segments, "<=", val),
    do: from(q in query, where: fragment("? #>> ? <= ?", q.payload, ^path_segments, ^val))

  defp dynamic_filter_text(query, _path_segments, _op, _val), do: query

  defp apply_result_sort(query, sort_by, _sort_dir, _fields, _source, _numeric_sort?) when sort_by in [nil, ""],
    do: query

  defp apply_result_sort(query, sort_by, sort_dir, fields, source, numeric_sort?) do
    direction = if sort_dir in ["desc", :desc], do: :desc, else: :asc

    fields
    |> Enum.find(fn field ->
      normalize_alias(field["alias"] || field[:alias], field["path"] || field[:path]) == sort_by
    end)
    |> case do
      nil ->
        query

      field ->
        path = field["path"] || field[:path]
        apply_source_sort(query, source, path, direction, numeric_sort?)
    end
  end

  defp apply_source_sort(query, "telemetry", path, :desc, true) when is_binary(path) do
    path_segments = String.split(path, ".", trim: true)
    from(q in query, order_by: [desc: fragment("nullif(? #>> ?, '')::numeric", q.payload, ^path_segments)])
  end

  defp apply_source_sort(query, "telemetry", path, :asc, true) when is_binary(path) do
    path_segments = String.split(path, ".", trim: true)
    from(q in query, order_by: [asc: fragment("nullif(? #>> ?, '')::numeric", q.payload, ^path_segments)])
  end

  defp apply_source_sort(query, "telemetry", path, :desc, _numeric_sort?) when is_binary(path) do
    path_segments = String.split(path, ".", trim: true)
    from(q in query, order_by: [desc: fragment("? #>> ?", q.payload, ^path_segments)])
  end

  defp apply_source_sort(query, "telemetry", path, :asc, _numeric_sort?) when is_binary(path) do
    path_segments = String.split(path, ".", trim: true)
    from(q in query, order_by: [asc: fragment("? #>> ?", q.payload, ^path_segments)])
  end

  defp apply_source_sort(query, "e2e", path, :desc, _numeric_sort?) do
    case field_atom_for("e2e", path) do
      nil -> query
      field_atom -> from(q in query, order_by: [desc: field(q, ^field_atom)])
    end
  end

  defp apply_source_sort(query, "e2e", path, :asc, _numeric_sort?) do
    case field_atom_for("e2e", path) do
      nil -> query
      field_atom -> from(q in query, order_by: [asc: field(q, ^field_atom)])
    end
  end

  defp apply_source_sort(query, _source, _path, _direction, _numeric_sort?), do: query

  defp telemetry_numeric_sort?("telemetry", sort_by, filters, opts) when is_binary(sort_by) and sort_by != "" do
    numeric_columns = opts[:numeric_columns] || opts["numeric_columns"] || []

    sort_by in numeric_columns or
      Enum.any?(filters, fn filter ->
        (filter["path"] || filter[:path] || filter["column"] || filter[:column]) == sort_by and
          numeric_filter?(filter)
      end)
  end

  defp telemetry_numeric_sort?(_source, _sort_by, _filters, _opts), do: false

  defp numeric_filter?(filter) do
    value = filter["value"] || filter[:value]
    operator = normalize_query_operator(filter["operator"] || filter[:operator])

    operator in [">", ">=", "<", "<="] or is_integer(value) or is_float(value)
  end

  defp apply_result_pagination(query, opts) do
    limit = opts[:limit] || opts["limit"] || @max_in_memory_rows
    offset = opts[:offset] || opts["offset"] || 0

    from(q in query,
      limit: ^normalize_non_negative_integer(limit, @max_in_memory_rows),
      offset: ^normalize_non_negative_integer(offset, 0)
    )
  end

  defp normalize_non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp normalize_non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> default
    end
  end

  defp normalize_non_negative_integer(_value, default), do: default

  defp normalize_query_operator("=="), do: "="
  defp normalize_query_operator("is"), do: "="
  defp normalize_query_operator("is not"), do: "!="
  defp normalize_query_operator("doesn't contain"), do: "not_contains"
  defp normalize_query_operator("doesnt contain"), do: "not_contains"
  defp normalize_query_operator(op), do: op

  defp parse_number(value) when is_integer(value) or is_float(value), do: {:ok, value}

  defp parse_number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parse_number(_value), do: :error
end
