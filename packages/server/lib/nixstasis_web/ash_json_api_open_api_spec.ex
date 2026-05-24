defmodule NixstasisWeb.AshJsonApiOpenAPISpec do
  @moduledoc """
  OpenAPI spec generator for Ash JSON:API routes.

  This module intentionally avoids `phoenix_endpoint` so `mix openapi.generate`
  can run without starting the application or connecting to the database.
  """

  @behaviour OpenApiSpex.OpenApi

  @impl OpenApiSpex.OpenApi
  def spec do
    AshJsonApi.OpenApi.spec(
      domains: [Nixstasis.Domain],
      open_api: "/open_api",
      open_api_title: "Nixstasis JSON API",
      open_api_version: "1.0.0",
      open_api_servers: ["http://localhost:4000"]
    )
  end
end
