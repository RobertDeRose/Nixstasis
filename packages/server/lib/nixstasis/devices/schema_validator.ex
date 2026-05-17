defmodule Nixstasis.Devices.SchemaValidator do
  @moduledoc """
  Validates device schema definitions.
  """

  def validate(schema_def) when is_map(schema_def) do
    with :ok <- require_json_schema_object(schema_def) do
      validate_optional_properties(schema_def)
    end
  end

  def validate(_), do: {:error, "schema must be a JSON object"}

  def validate_registration(schema_def, scope \\ :public)

  def validate_registration(schema_def, :public) when is_map(schema_def) do
    with :ok <- require_non_empty_schema(schema_def),
         :ok <- require_product(schema_def),
         :ok <- require_json_schema_object(schema_def) do
      require_properties_object(schema_def)
    end
  end

  def validate_registration(schema_def, :internal) when is_map(schema_def) and map_size(schema_def) == 0,
    do: :ok

  def validate_registration(schema_def, :internal) when is_map(schema_def) do
    with :ok <- require_product(schema_def),
         :ok <- require_json_schema_object(schema_def) do
      require_properties_object(schema_def)
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
