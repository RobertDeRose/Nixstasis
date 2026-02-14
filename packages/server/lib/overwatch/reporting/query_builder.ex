defmodule Nixstasis.Reporting.QueryBuilder do
  @moduledoc """
  Builds dynamic report queries from configuration.
  """

  import Ecto.Query

  alias Nixstasis.Domain
  alias Nixstasis.E2E.Run
  alias Nixstasis.Monitoring.Telemetry

  @telemetry_fields ~w(id device_id timestamp inserted_at updated_at)a
  @e2e_fields ~w(id suite_id journey_ids environment_label trigger_source protocol_version status started_at finished_at inserted_at updated_at)a

  @telemetry_field_lookup Map.new(@telemetry_fields, &{Atom.to_string(&1), &1})
  @e2e_field_lookup Map.new(@e2e_fields, &{Atom.to_string(&1), &1})

  @e2e_default_fields [
    %{"path" => "id", "alias" => "run_id"},
    %{"path" => "suite_id", "alias" => "suite"},
    %{"path" => "environment_label", "alias" => "environment"},
    %{"path" => "status", "alias" => "status"},
    %{"path" => "started_at", "alias" => "started_at"},
    %{"path" => "finished_at", "alias" => "finished_at"}
  ]

  def build(config) do
    source = normalize_source(config["source"] || config[:source])
    fields = fields_for_report(config)
    filters = config["filters"] || config[:filters] || []

    source
    |> base_query()
    |> select_fields(fields, source)
    |> apply_filters(filters, source)
  end

  def fields_for_report(config) do
    source = normalize_source(config["source"] || config[:source])
    fields = config["fields"] || config[:fields] || []

    case {source, fields} do
      {"e2e", []} -> @e2e_default_fields
      _ -> fields
    end
  end

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
        case op do
          "=" -> from(q in query, where: field(q, ^field_atom) == ^val)
          "!=" -> from(q in query, where: field(q, ^field_atom) != ^val)
          ">" -> from(q in query, where: field(q, ^field_atom) > ^val)
          "<" -> from(q in query, where: field(q, ^field_atom) < ^val)
          _ -> query
        end
    end
  end

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
    cast_type =
      if is_integer(val) or is_float(val) do
        "::numeric"
      else
        ""
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
    path_segments = String.split(path, ".", trim: true)

    case op do
      "=" ->
        if cast_type == "::numeric" do
          from(q in query, where: fragment("( ? #>> ? )::numeric = ?", q.payload, ^path_segments, ^val))
        else
          from(q in query, where: fragment("? #>> ? = ?", q.payload, ^path_segments, ^val))
        end

      ">" ->
        if cast_type == "::numeric" do
          from(q in query, where: fragment("( ? #>> ? )::numeric > ?", q.payload, ^path_segments, ^val))
        else
          from(q in query, where: fragment("? #>> ? > ?", q.payload, ^path_segments, ^val))
        end

      "<" ->
        if cast_type == "::numeric" do
          from(q in query, where: fragment("( ? #>> ? )::numeric < ?", q.payload, ^path_segments, ^val))
        else
          from(q in query, where: fragment("? #>> ? < ?", q.payload, ^path_segments, ^val))
        end

      _ ->
        query
    end
  end
end
