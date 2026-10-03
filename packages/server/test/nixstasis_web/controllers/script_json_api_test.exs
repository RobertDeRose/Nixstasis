defmodule NixstasisWeb.ScriptJSONAPITest do
  use NixstasisWeb.ConnCase

  @script_resource_paths [
    "/api/json/script_drafts",
    "/api/json/script_versions",
    "/api/json/script_validation_runs",
    "/api/json/script_test_runs",
    "/api/json/script_deployment_runs",
    "/api/json/script_client_actions"
  ]

  setup do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn ->
      Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous)
    end)

    :ok
  end

  test "script workbench resources are not exposed as generic JSON:API routes", %{conn: conn} do
    for path <- @script_resource_paths do
      assert response(
               conn
               |> recycle()
               |> put_req_header("accept", "application/vnd.api+json")
               |> put_req_header("x-token-user-roles", "nixstasis/viewer")
               |> get(path),
               404
             )
    end
  end
end
