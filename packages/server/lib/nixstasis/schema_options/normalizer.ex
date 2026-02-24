defmodule Nixstasis.SchemaOptions.Normalizer do
  @moduledoc """
  Normalizes device schema maps into deterministic dropdown options.
  """

  @doc """
  Converts a schema map to normalized options.
  """
  def normalize(schema) when is_map(schema) do
    schema
    |> extract_candidate_paths()
    |> Enum.uniq()
    |> Enum.sort()
    |> disambiguate_labels()
    |> Enum.with_index()
    |> Enum.map(fn {{key, label}, idx} ->
      %{
        key: key,
        label: label,
        value_type: infer_type(schema, key),
        order_index: idx,
        selectable: true
      }
    end)
  end

  def normalize(_), do: []

  defp extract_candidate_paths(schema) do
    cond do
      is_map(schema["properties"]) -> flatten_properties(schema["properties"])
      is_map(schema[:properties]) -> flatten_properties(schema[:properties])
      true -> flatten_generic(schema)
    end
  end

  defp flatten_properties(props, prefix \\ []) do
    props
    |> Enum.flat_map(fn {raw_key, value} ->
      key = to_string(raw_key)
      path = prefix ++ [key]

      cond do
        is_map(value) and is_map(value["properties"]) ->
          flatten_properties(value["properties"], path)

        is_map(value) and is_map(value[:properties]) ->
          flatten_properties(value[:properties], path)

        true ->
          [Enum.join(path, ".")]
      end
    end)
  end

  defp flatten_generic(map, prefix \\ [])

  defp flatten_generic(map, prefix) when is_map(map) do
    map
    |> Enum.flat_map(fn {raw_key, value} ->
      key = to_string(raw_key)
      path = prefix ++ [key]

      cond do
        is_map(value) and map_size(value) > 0 ->
          flatten_generic(value, path)

        is_list(value) and value != [] ->
          [Enum.join(path, ".")]

        true ->
          [Enum.join(path, ".")]
      end
    end)
  end

  defp flatten_generic(_, _), do: []

  defp disambiguate_labels(paths) do
    labels =
      Enum.group_by(paths, fn path ->
        path |> String.split(".") |> List.last() |> humanize()
      end)

    Enum.map(paths, fn path ->
      base_label = path |> String.split(".") |> List.last() |> humanize()

      label =
        case Map.get(labels, base_label, []) do
          [_single] -> base_label
          _many -> "#{base_label} (#{path})"
        end

      {path, label}
    end)
  end

  defp infer_type(schema, key) do
    schema
    |> get_in_properties(key)
    |> case do
      %{"type" => type} when is_binary(type) -> type
      %{type: type} when is_binary(type) -> type
      _ -> "unknown"
    end
  end

  defp get_in_properties(schema, key) do
    keys = String.split(key, ".")

    Enum.reduce_while(keys, schema, fn segment, acc ->
      case next_segment_map(acc, segment) do
        nil -> {:halt, %{}}
        next -> {:cont, next}
      end
    end)
  end

  defp next_segment_map(acc, segment) when is_map(acc) do
    direct =
      [get_nested_map(acc, "properties", segment), get_nested_map(acc, :properties, segment), get_map(acc, segment)]
      |> Enum.find(&is_map/1)

    direct || atom_segment_map(acc, segment)
  end

  defp next_segment_map(_acc, _segment), do: nil

  defp get_nested_map(map, parent, segment) do
    nested = Map.get(map, parent)
    if is_map(nested), do: get_map(nested, segment), else: nil
  end

  defp get_map(map, key) when is_map(map), do: Map.get(map, key)
  defp get_map(_map, _key), do: nil

  defp atom_segment_map(acc, segment) do
    acc
    |> Map.keys()
    |> Enum.find(fn key -> is_atom(key) and Atom.to_string(key) == segment end)
    |> case do
      nil -> nil
      atom_key -> get_map(acc, atom_key)
    end
  end

  defp humanize(value) do
    value
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
