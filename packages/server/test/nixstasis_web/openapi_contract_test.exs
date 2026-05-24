defmodule NixstasisWeb.OpenAPIContractTest do
  use ExUnit.Case, async: true

  @openapi_path Path.expand("../../priv/static/openapi.yaml", __DIR__)

  test "generated OpenAPI includes builder contract action routes" do
    openapi = File.read!(@openapi_path)

    assert openapi =~ "/api/json/builder_contract/schema_references:"

    assert openapi =~
             "/api/json/builder_contract/schemas/{schema_id}/versions/{schema_version}/options:"

    assert openapi =~ "/api/json/builder_contract/builder_configurations/validate:"
  end

  test "generated OpenAPI includes builder contract schema fields" do
    openapi = File.read!(@openapi_path)

    assert openapi =~ "operationId: list_builder_schema_references"
    assert openapi =~ "schema_id:"
    assert openapi =~ "schema_version:"
    assert openapi =~ "product_name:"
    assert openapi =~ "readable:"

    assert openapi =~ "operationId: get_builder_schema_options"
    assert openapi =~ "status:"
    assert openapi =~ "payload:"
    assert openapi =~ "options:"
    assert openapi =~ "value_type:"

    assert openapi =~ "operationId: validate_builder_configuration"
    assert openapi =~ "selections:"
    assert openapi =~ "cleared_slot_ids:"
    assert openapi =~ "issue_code:"
    assert openapi =~ "blocking:"
  end
end
