defmodule Nixstasis.Devices.SchemaValidator do
  @moduledoc """
  Validates device schema definitions.
  """

  @max_schema_bytes 65_536
  @max_schema_depth 8
  @max_schema_fields 256

  @doc "Returns the enforced schema resource limits."
  def limits do
    %{max_bytes: @max_schema_bytes, max_depth: @max_schema_depth, max_fields: @max_schema_fields}
  end

  def validate(schema_def) when is_map(schema_def) do
    with :ok <- require_json_schema_object(schema_def),
         :ok <- validate_optional_properties(schema_def) do
      validate_limits(schema_def)
    end
  end

  def validate(_), do: {:error, "schema must be a JSON object"}

  def validate_registration(schema_def, scope \\ :public)

  def validate_registration(schema_def, :public) when is_map(schema_def) do
    with :ok <- require_non_empty_schema(schema_def),
         :ok <- require_product(schema_def),
         :ok <- require_json_schema_object(schema_def),
         :ok <- require_properties_object(schema_def) do
      validate_limits(schema_def)
    end
  end

  def validate_registration(schema_def, :internal) when is_map(schema_def) and map_size(schema_def) == 0,
    do: :ok

  def validate_registration(schema_def, :internal) when is_map(schema_def) do
    with :ok <- require_product(schema_def),
         :ok <- require_json_schema_object(schema_def),
         :ok <- require_properties_object(schema_def) do
      validate_limits(schema_def)
    end
  end

  def validate_registration(_schema_def, scope) when scope in [:public, :internal],
    do: {:error, "schema must be a JSON object"}

  def validate_registration(schema_def, _scope), do: validate_registration(schema_def, :public)

  defp require_non_empty_schema(schema_def) when map_size(schema_def) == 0,
    do: {:error, "schema must include product"}

  defp require_non_empty_schema(_schema_def), do: :ok

  defp require_product(schema_def) do
    case fetch_string(schema_def, "product") do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, "schema product must be a non-empty string"},
          else: :ok

      _ ->
        {:error, "schema must include product"}
    end
  end

  defp require_json_schema_object(schema_def) do
    case fetch_string(schema_def, "type") do
      nil -> :ok
      "object" -> :ok
      _ -> {:error, "schema type must be object"}
    end
  end

  defp require_properties_object(schema_def) do
    case fetch_key(schema_def, "properties") do
      properties when is_map(properties) -> :ok
      _ -> {:error, "schema properties must be a JSON object"}
    end
  end

  defp validate_optional_properties(schema_def) do
    case fetch_key(schema_def, "properties") do
      nil -> :ok
      properties when is_map(properties) -> :ok
      _ -> {:error, "schema properties must be a JSON object"}
    end
  end

  defp validate_limits(schema_def) do
    with :ok <- validate_encoded_size(schema_def) do
      case walk_schema(schema_def, 0, 0) do
        {:ok, _field_count} -> :ok
        {:error, :depth} -> {:error, "schema exceeds maximum nesting depth of #{@max_schema_depth}"}
        {:error, :fields} -> {:error, "schema exceeds maximum field count of #{@max_schema_fields}"}
      end
    end
  end

  defp validate_encoded_size(schema_def) do
    case Jason.encode(schema_def) do
      {:ok, encoded} when byte_size(encoded) <= @max_schema_bytes -> :ok
      {:ok, _encoded} -> {:error, "schema exceeds maximum size of #{@max_schema_bytes} bytes"}
      {:error, _reason} -> {:error, "schema must contain only JSON-compatible values"}
    end
  end

  defp walk_schema(_value, depth, _field_count) when depth > @max_schema_depth,
    do: {:error, :depth}

  defp walk_schema(value, _depth, field_count)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: {:ok, field_count}

  defp walk_schema(value, depth, field_count) when is_map(value) do
    next_field_count = field_count + map_size(value)

    if next_field_count > @max_schema_fields do
      {:error, :fields}
    else
      Enum.reduce_while(value, {:ok, next_field_count}, fn {_key, child}, {:ok, count} ->
        case walk_schema(child, depth + 1, count) do
          {:ok, next_count} -> {:cont, {:ok, next_count}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp walk_schema(value, depth, field_count) when is_list(value) do
    Enum.reduce_while(value, {:ok, field_count}, fn child, {:ok, count} ->
      case walk_schema(child, depth + 1, count) do
        {:ok, next_count} -> {:cont, {:ok, next_count}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp walk_schema(_value, _depth, _field_count), do: {:error, :json}

  defp fetch_string(map, key) do
    case fetch_key(map, key) do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp fetch_key(map, key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end
end
