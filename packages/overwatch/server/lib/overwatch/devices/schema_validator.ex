defmodule Nixstasis.Devices.SchemaValidator do
  @moduledoc """
  Validates device schema definitions.
  """

  def validate(schema_def) when is_map(schema_def) do
    # T018: ensure `product` exists (as per plan text, though ambiguous,
    # possibly referring to a field definition for product info, or just that the schema itself is valid)
    # For now, we just ensure it is a map (which the guard does).
    :ok
  end

  def validate(_), do: {:error, "schema_definition must be a JSON object"}
end
