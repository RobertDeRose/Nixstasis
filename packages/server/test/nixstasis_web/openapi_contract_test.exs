defmodule NixstasisWeb.OpenAPIContractTest do
  use ExUnit.Case, async: true

  @openapi_path Path.expand("../../priv/static/openapi.yaml", __DIR__)
  @script_resource_names ~w(
    script_drafts
    script_versions
    script_validation_runs
    script_test_runs
    script_deployment_runs
    script_client_actions
  )

  test "generated OpenAPI includes builder contract action routes" do
    openapi = File.read!(@openapi_path)

    assert openapi =~ "/api/json/builder_contract/schema_references:"

    assert openapi =~
             "/api/json/builder_contract/schemas/{schema_id}/versions/{schema_version}/options:"

    assert openapi =~ "/api/json/builder_contract/builder_configurations/validate:"
  end

  test "generated OpenAPI includes device runtime registration/list routes and security" do
    openapi = YamlElixir.read_from_file!(@openapi_path)

    list_operation = get_in(openapi, ["paths", "/api/json/device_runtime/devices", "get"])

    registration_operation =
      get_in(openapi, ["paths", "/api/json/device_runtime/devices/register", "post"])

    assert list_operation["operationId"] == "list_runtime_devices"
    assert registration_operation["operationId"] == "register_runtime_device"
    assert list_operation["security"] == [%{"bearerAuth" => []}]
    assert registration_operation["security"] == []
    assert get_in(openapi, ["components", "securitySchemes", "deviceApiKey", "type"]) == "apiKey"
    assert get_in(openapi, ["components", "securitySchemes", "deviceApiKey", "in"]) == "query"
    assert get_in(openapi, ["components", "securitySchemes", "deviceApiKey", "name"]) == "api_key"
  end

  test "generated OpenAPI includes heartbeat action fields and its 200 status" do
    openapi = YamlElixir.read_from_file!(@openapi_path)

    heartbeat =
      get_in(openapi, [
        "paths",
        "/api/json/device_runtime/devices/{device_id}/heartbeat",
        "post"
      ])

    assert heartbeat["operationId"] == "heartbeat"
    assert heartbeat["security"] == [%{"deviceApiKey" => []}]
    assert Map.has_key?(heartbeat["responses"], "200")
    refute Map.has_key?(heartbeat["responses"], "201")

    request_properties =
      get_in(heartbeat, [
        "requestBody",
        "content",
        "application/vnd.api+json",
        "schema",
        "properties",
        "data",
        "properties"
      ])

    assert Map.has_key?(request_properties, "telemetry")
    assert Map.has_key?(request_properties, "connection_status")
    assert Map.has_key?(request_properties, "command_inventory")
  end

  test "generated OpenAPI includes command result and payload action contracts" do
    openapi = YamlElixir.read_from_file!(@openapi_path)

    command_results =
      get_in(openapi, [
        "paths",
        "/api/json/device_runtime/devices/{device_id}/command_results",
        "post"
      ])

    payload =
      get_in(openapi, [
        "paths",
        "/api/json/device_runtime/devices/{device_id}/command_payloads/{ref}",
        "get"
      ])

    assert command_results["operationId"] == "acknowledge_command_results"
    assert command_results["security"] == [%{"deviceApiKey" => []}]
    assert Map.has_key?(command_results["responses"], "202")
    refute Map.has_key?(command_results["responses"], "201")

    results_properties =
      get_in(command_results, [
        "requestBody",
        "content",
        "application/vnd.api+json",
        "schema",
        "properties",
        "data",
        "properties"
      ])

    assert Map.has_key?(results_properties, "results")
    assert payload["operationId"] == "fetch_command_payload"
    assert payload["security"] == [%{"deviceApiKey" => []}]
    assert Map.has_key?(payload["responses"], "200")
  end

  test "generated OpenAPI documents device runtime failure statuses" do
    openapi = YamlElixir.read_from_file!(@openapi_path)

    expected = [
      {"/api/json/device_runtime/devices", "get", ~w(403 429)},
      {"/api/json/device_runtime/devices/register", "post", ~w(400 429)},
      {"/api/json/device_runtime/devices/{device_id}/heartbeat", "post", ~w(400 401 403 404 429)},
      {"/api/json/device_runtime/devices/{device_id}/command_results", "post", ~w(400 401 403 404 429)},
      {"/api/json/device_runtime/devices/{device_id}/command_payloads/{ref}", "get", ~w(401 403 404 429)}
    ]

    for {path, verb, statuses} <- expected do
      responses = get_in(openapi, ["paths", path, verb, "responses"])

      for status <- statuses do
        assert Map.has_key?(responses, status), "missing #{status} response for #{verb} #{path}"
      end
    end
  end

  test "generated OpenAPI excludes internal script workbench resources" do
    openapi = YamlElixir.read_from_file!(@openapi_path)

    for resource <- @script_resource_names do
      collection_path = "/api/json/#{resource}"
      member_path = "#{collection_path}/{id}"

      refute Map.has_key?(openapi["paths"], collection_path)
      refute Map.has_key?(openapi["paths"], member_path)
    end
  end

  test "generated OpenAPI includes builder contract schema fields" do
    openapi = File.read!(@openapi_path)

    assert openapi =~ "operationId: list_builder_schema_references"
    assert openapi =~ "schema_id:"
    assert openapi =~ "schema_version:"
    assert openapi =~ "product_name:"
    assert openapi =~ "readable:"

    assert openapi =~ "operationId: get_builder_schema_options"
    assert openapi =~ "options:"
    assert openapi =~ "load_time_ms:"
    assert openapi =~ "value_type:"

    assert openapi =~ "operationId: validate_builder_configuration"
    assert openapi =~ "selections:"
    assert openapi =~ "cleared_slot_ids:"
    assert openapi =~ "issue_code:"
    assert openapi =~ "blocking:"
    assert openapi =~ ~r/builder:\n\s+enum:\n\s+- alert\n\s+- report/
    assert openapi =~ ~r/load_time_ms:\n\s+minimum: 0\n\s+type: integer/
  end

  test "generated OpenAPI includes builder contract error responses" do
    openapi = YamlElixir.read_from_file!(@openapi_path)

    validate_responses =
      get_in(openapi, [
        "paths",
        "/api/json/builder_contract/builder_configurations/validate",
        "post",
        "responses"
      ])

    options_responses =
      get_in(openapi, [
        "paths",
        "/api/json/builder_contract/schemas/{schema_id}/versions/{schema_version}/options",
        "get",
        "responses"
      ])

    schema_references_responses =
      get_in(openapi, [
        "paths",
        "/api/json/builder_contract/schema_references",
        "get",
        "responses"
      ])

    assert_error_response(validate_responses, "400")
    assert_error_response(validate_responses, "403")
    assert_error_response(options_responses, "400")
    assert_error_response(options_responses, "403")
    assert_error_response(options_responses, "404")
    assert_error_response(schema_references_responses, "403")
  end

  defp assert_error_response(responses, status) do
    assert get_in(responses, [
             status,
             "content",
             "application/vnd.api+json",
             "schema",
             "properties",
             "errors",
             "$ref"
           ]) == "#/components/schemas/errors"

    assert get_in(responses, [status, "description"]) == "JSON:API error response"
  end

  test "generated OpenAPI preserves existing resource fields" do
    openapi = File.read!(@openapi_path)

    assert openapi =~ "mac_address:"
    assert openapi =~ "approval_status:"
    assert openapi =~ "remote_access_requested:"
    assert openapi =~ "condition_field:"
    assert openapi =~ "threshold_value:"
    assert openapi =~ "pending_commands:"
    assert openapi =~ "telemetry_events:"
    assert openapi =~ "alerts:"
  end

  test "generated OpenAPI uses relative server URL" do
    openapi = File.read!(@openapi_path)

    assert openapi =~ "url: /"
    refute openapi =~ "http://localhost:4000"
  end

  test "generated OpenAPI documents bearer auth for JSON API routes" do
    openapi = File.read!(@openapi_path)

    assert openapi =~ "bearerAuth:"
    assert openapi =~ ~r/security:\n\s+- bearerAuth: \[\]/
  end
end
