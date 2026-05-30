defmodule NixstasisWeb.BuilderContractJSONAPITest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:77",
        "product_name" => "jsonapi-v1",
        "schema" => %{
          "product" => "jsonapi-v1",
          "version" => "v1",
          "properties" => %{"temp" => %{"type" => "number"}}
        }
      })

    :ok
  end

  test "GET /api/json/builder_contract/schema_references returns encoded action data", %{conn: conn} do
    conn = get(conn, "/api/json/builder_contract/schema_references")
    body = json_response(conn, 200)

    assert Enum.any?(body, &(&1["schema_id"] == "jsonapi-v1"))
  end

  test "GET /api/json/builder_contract/schemas/:id/versions/:version/options returns options payload", %{
    conn: conn
  } do
    conn = get(conn, "/api/json/builder_contract/schemas/jsonapi-v1/versions/v1/options?builder=alert")
    body = json_response(conn, 200)

    assert body["schema_id"] == "jsonapi-v1"
    assert body["builder"] == "alert"
    assert body["load_time_ms"] >= 0
  end

  test "GET /api/json/builder_contract/schemas/:id/versions/:version/options defaults builder", %{
    conn: conn
  } do
    conn = get(conn, "/api/json/builder_contract/schemas/jsonapi-v1/versions/v1/options")

    assert %{"builder" => "alert", "schema_id" => "jsonapi-v1"} = json_response(conn, 200)
  end

  test "GET /api/json/builder_contract/schemas/:id/versions/:version/options returns 404", %{
    conn: conn
  } do
    conn = get(conn, "/api/json/builder_contract/schemas/missing/versions/v1/options?builder=alert")

    body = json_response(conn, 404)
    assert %{"errors" => [%{"code" => "not_found"}]} = body
  end

  test "GET /api/json/builder_contract/schemas/:id/versions/:version/options rejects invalid builders", %{
    conn: conn
  } do
    conn = get(conn, "/api/json/builder_contract/schemas/jsonapi-v1/versions/v1/options?builder=unknown")

    assert %{"errors" => [%{"code" => "invalid_query"}]} = json_response(conn, 400)
  end

  test "POST /api/json/builder_contract/builder_configurations/validate returns validation data", %{
    conn: conn
  } do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/builder_contract/builder_configurations/validate", %{
        "data" => %{
          "builder" => "report",
          "schema_id" => "jsonapi-v1",
          "schema_version" => "v1",
          "selections" => [%{"slot_id" => "a", "selected_key" => "missing"}]
        }
      })

    body = json_response(conn, 201)

    assert %{"valid" => false, "cleared_slot_ids" => ["a"]} = body
  end

  test "POST /api/json/builder_contract/builder_configurations/validate rejects invalid builders", %{
    conn: conn
  } do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/builder_contract/builder_configurations/validate", %{
        "data" => %{
          "builder" => "unknown",
          "schema_id" => "jsonapi-v1",
          "schema_version" => "v1",
          "selections" => [%{"slot_id" => "a", "selected_key" => "temp"}]
        }
      })

    assert %{"errors" => [%{"code" => "invalid_body"}]} = json_response(conn, 400)
  end

  test "alert-rule JSON:API read requires viewer role when local fallback is disabled", %{conn: conn} do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    assert %{"errors" => [%{"code" => "forbidden"}]} =
             conn
             |> put_req_header("accept", "application/vnd.api+json")
             |> get("/api/json/alert_rules")
             |> json_response(403)

    conn =
      conn
      |> recycle()
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> get("/api/json/alert_rules")

    assert %{"data" => []} = json_response(conn, 200)
  end

  test "alert-rule JSON:API writes require manager role when local fallback is disabled", %{conn: conn} do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    params = %{
      "data" => %{
        "type" => "alert_rule",
        "attributes" => %{
          "name" => "High temp",
          "product_name" => "jsonapi-v1",
          "condition_field" => "temp",
          "operator" => ">",
          "threshold_value" => "70"
        }
      }
    }

    assert %{"errors" => [%{"code" => "forbidden"}]} =
             conn
             |> put_req_header("accept", "application/vnd.api+json")
             |> put_req_header("content-type", "application/vnd.api+json")
             |> put_req_header("x-token-user-roles", "nixstasis/viewer")
             |> post("/api/json/alert_rules", params)
             |> json_response(403)

    conn =
      conn
      |> recycle()
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> put_req_header("x-token-user-roles", "nixstasis/operator")
      |> post("/api/json/alert_rules", params)

    assert %{"data" => %{"type" => "alert_rule"}} = json_response(conn, 201)
  end
end
