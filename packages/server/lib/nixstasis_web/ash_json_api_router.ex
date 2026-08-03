defmodule NixstasisWeb.AshJsonApiRouter do
  @moduledoc """
  The AshJsonApiRouter for the Nixstasis application.
  This router defines the JSON API endpoints for resources in the Nixstasis system,
  leveraging the AshJsonApi library for seamless integration with Ash resources.
  It also provides OpenAPI documentation for the defined endpoints.
  """

  use AshJsonApi.Router,
    domains: [Nixstasis.Domain],
    open_api: "/open_api",
    open_api_title: "Nixstasis JSON API",
    open_api_version: "1.0.0",
    open_api_servers: ["/"],
    modify_open_api: {__MODULE__, :modify_open_api, []},
    phoenix_endpoint: NixstasisWeb.Endpoint

  def modify_open_api(spec, _conn, _opts) do
    spec
    |> Map.update!(:security, fn _security -> [%{"bearerAuth" => []}] end)
    |> put_device_runtime_security()
    |> put_builder_load_time_minimum()
    |> put_builder_error_responses()
  end

  defp put_device_runtime_security(%{paths: paths, components: components} = spec) do
    paths =
      paths
      |> put_operation_security(
        "/api/json/device_runtime/devices",
        :get,
        [%{"bearerAuth" => []}]
      )
      |> put_operation_security(
        "/api/json/device_runtime/devices/register",
        :post,
        []
      )
      |> put_operation_security(
        "/api/json/device_runtime/devices/{device_id}/heartbeat",
        :post,
        [%{"deviceApiKey" => []}]
      )
      |> put_operation_security(
        "/api/json/device_runtime/devices/{device_id}/command_results",
        :post,
        [%{"deviceApiKey" => []}]
      )
      |> put_operation_security(
        "/api/json/device_runtime/devices/{device_id}/command_payloads/{ref}",
        :get,
        [%{"deviceApiKey" => []}]
      )

    security_schemes =
      (components.securitySchemes || %{})
      |> Map.put(
        "deviceApiKey",
        %OpenApiSpex.SecurityScheme{
          type: "apiKey",
          in: "query",
          name: "api_key",
          description: "Registration-issued device token for runtime operations."
        }
      )

    %{spec | paths: paths, components: %{components | securitySchemes: security_schemes}}
  end

  defp put_operation_security(paths, path, verb, security) do
    case Map.get(paths, path) do
      nil ->
        paths

      path_item ->
        Map.put(paths, path, Map.update!(path_item, verb, &%{&1 | security: security}))
    end
  end

  defp put_builder_error_responses(%{paths: paths} = spec) do
    validate_path = "/api/json/builder_contract/builder_configurations/validate"
    schema_references_path = "/api/json/builder_contract/schema_references"
    options_path = "/api/json/builder_contract/schemas/{schema_id}/versions/{schema_version}/options"

    updated_paths =
      paths
      |> put_in([schema_references_path, Access.key!(:get), Access.key!(:responses), 403], error_response())
      |> put_in([validate_path, Access.key!(:post), Access.key!(:responses), 400], error_response())
      |> put_in([validate_path, Access.key!(:post), Access.key!(:responses), 403], error_response())
      |> put_in([options_path, Access.key!(:get), Access.key!(:responses), 400], error_response())
      |> put_in([options_path, Access.key!(:get), Access.key!(:responses), 403], error_response())
      |> put_in([options_path, Access.key!(:get), Access.key!(:responses), 404], error_response())

    %{spec | paths: updated_paths}
  end

  defp put_builder_load_time_minimum(%{paths: paths} = spec) do
    path = "/api/json/builder_contract/schemas/{schema_id}/versions/{schema_version}/options"

    updated_paths =
      update_in(
        paths,
        [
          path,
          Access.key!(:get),
          Access.key!(:responses),
          200,
          Access.key!(:content),
          "application/vnd.api+json",
          Access.key!(:schema),
          Access.key!(:properties),
          :load_time_ms
        ],
        &%{&1 | minimum: 0}
      )

    %{spec | paths: updated_paths}
  end

  defp error_response do
    %{
      description: "JSON:API error response",
      content: %{
        "application/vnd.api+json" => %{
          schema: %{
            type: "object",
            required: [:errors],
            properties: %{errors: %{"$ref" => "#/components/schemas/errors"}}
          }
        }
      }
    }
  end
end
