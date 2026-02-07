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
    phoenix_endpoint: NixstasisWeb.Endpoint
end
