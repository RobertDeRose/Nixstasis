defmodule NixstasisWeb.AshJsonApiOpenAPISpec do
  @moduledoc """
  OpenAPI spec generator for Ash JSON:API routes.

  This module delegates to the Ash JSON:API router so generated OpenAPI uses
  the same router options as runtime without starting the application.
  """

  @behaviour OpenApiSpex.OpenApi

  @impl OpenApiSpex.OpenApi
  def spec do
    NixstasisWeb.AshJsonApiRouter.spec()
  end
end
