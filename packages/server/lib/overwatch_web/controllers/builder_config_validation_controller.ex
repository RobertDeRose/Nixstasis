defmodule NixstasisWeb.BuilderConfigValidationController do
  use NixstasisWeb, :controller

  alias Nixstasis.SchemaOptions

  def create(conn, params) do
    builder = Map.get(params, "builder")
    schema_id = Map.get(params, "schema_id")
    schema_version = Map.get(params, "schema_version")
    selections = Map.get(params, "selections", [])

    validation = SchemaOptions.validate_selections(builder, schema_id, schema_version, selections)
    render(conn, :show, validation: validation)
  end
end
