defmodule NixstasisWeb.BuilderConfigValidationController do
  use NixstasisWeb, :controller

  alias Nixstasis.Domain

  def create(conn, params) do
    builder = Map.get(params, "builder")
    schema_id = Map.get(params, "schema_id")
    schema_version = Map.get(params, "schema_version")
    selections = Map.get(params, "selections")

    if valid_request?(builder, schema_id, schema_version, selections) do
      validation = Domain.validate_builder_configuration!(builder, schema_id, schema_version, selections)

      render(conn, :show, validation: validation)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: %{code: "invalid_validation_payload", message: "Invalid validation payload"}})
    end
  end

  defp valid_request?(builder, schema_id, schema_version, selections) do
    valid_builder?(builder) and is_binary(schema_id) and is_binary(schema_version) and is_list(selections) and
      Enum.all?(selections, &valid_selection?/1)
  end

  defp valid_builder?(builder), do: builder in ["alert", "report"]

  defp valid_selection?(selection) when is_map(selection) do
    is_binary(Map.get(selection, "slot_id") || Map.get(selection, :slot_id)) and
      is_binary(Map.get(selection, "selected_key") || Map.get(selection, :selected_key))
  end

  defp valid_selection?(_selection), do: false
end
