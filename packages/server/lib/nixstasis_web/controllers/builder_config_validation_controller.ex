defmodule NixstasisWeb.BuilderConfigValidationController do
  use NixstasisWeb, :controller

  alias Nixstasis.Domain

  def create(conn, params) do
    builder = Map.get(params, "builder")
    schema_id = Map.get(params, "schema_id")
    schema_version = Map.get(params, "schema_version")
    selections = Map.get(params, "selections", [])

    validation =
      if is_list(selections) do
        Domain.validate_builder_configuration!(builder, schema_id, schema_version, selections)
      else
        %{valid: false, issues: [], cleared_slot_ids: []}
      end

    render(conn, :show, validation: validation)
  end
end
