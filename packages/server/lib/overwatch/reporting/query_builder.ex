defmodule Nixstasis.Reporting.QueryBuilder do
  @moduledoc """
  Builds dynamic telemetry report queries from configuration.
  """

  import Ecto.Query
  alias Nixstasis.Monitoring.Telemetry

  def build(config) do
    source = config["source"] || config[:source]
    fields = config["fields"] || config[:fields] || []
    filters = config["filters"] || config[:filters] || []

    base_query(source)
    |> select_fields(fields)
    |> apply_filters(filters)
  end

  defp base_query("telemetry") do
    from(t in Telemetry, as: :telemetry)
  end

  defp select_fields(query, fields) do
    select_map =
      Enum.into(fields, %{}, fn field ->
        alias_name = field["alias"] || field[:alias]
        path = field["path"] || field[:path]
        {alias_name, build_path_selection(path)}
      end)

    from(q in query, select: ^select_map)
  end

  defp build_path_selection(path) do
    # We use -> because we want the raw JSON value (number, bool, etc)
    # properly decoded by Ecto, not just a string string.
    dynamic([t], fragment("?->?", t.payload, ^path))
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc ->
      apply_filter(acc, filter)
    end)
  end

  # Handle standard schema fields (like device_id)
  defp apply_filter(query, filter) do
    # Normalize access
    field = filter["field"] || filter[:field]
    path = filter["path"] || filter[:path]
    op = filter["operator"] || filter[:operator]
    val = filter["value"] || filter[:value]

    cond do
      field -> apply_schema_filter(query, field, op, val)
      path -> apply_json_path_filter(query, path, op, val)
      true -> query
    end
  end

  defp apply_schema_filter(query, field, op, val) do
    field_atom = String.to_existing_atom(field)

    case op do
      "=" -> from(q in query, where: field(q, ^field_atom) == ^val)
      "!=" -> from(q in query, where: field(q, ^field_atom) != ^val)
      ">" -> from(q in query, where: field(q, ^field_atom) > ^val)
      "<" -> from(q in query, where: field(q, ^field_atom) < ^val)
      _ -> query
    end
  end

  defp apply_json_path_filter(query, path, op, val) do
    # Determine casting based on value type
    {cast_type, _val_to_compare} =
      if is_integer(val) or is_float(val) do
        {"::numeric", val}
      else
        # Default to string comparison
        {"", val}
      end

    case op do
      "=" ->
        dynamic_filter(query, path, "=", val, cast_type)

      ">" ->
        dynamic_filter(query, path, ">", val, cast_type)

      "<" ->
        dynamic_filter(query, path, "<", val, cast_type)

      _ ->
        query
    end
  end

  defp dynamic_filter(query, path, op, val, cast_type) do
    # We use macros to construct the fragment safely
    # Note: Ecto doesn't support dynamic fragments with variable operators easily
    # So we dispatch based on op

    case op do
      "=" ->
        if cast_type == "::numeric" do
          from(q in query, where: fragment("(?->>?)::numeric = ?", q.payload, ^path, ^val))
        else
          from(q in query, where: fragment("?->>? = ?", q.payload, ^path, ^val))
        end

      ">" ->
        if cast_type == "::numeric" do
          from(q in query, where: fragment("(?->>?)::numeric > ?", q.payload, ^path, ^val))
        else
          from(q in query, where: fragment("?->>? > ?", q.payload, ^path, ^val))
        end

      "<" ->
        if cast_type == "::numeric" do
          from(q in query, where: fragment("(?->>?)::numeric < ?", q.payload, ^path, ^val))
        else
          from(q in query, where: fragment("?->>? < ?", q.payload, ^path, ^val))
        end

      _ ->
        query
    end
  end
end
