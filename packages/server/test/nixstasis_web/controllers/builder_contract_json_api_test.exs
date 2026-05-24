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

  test "GET /api/json/builder_contract/schemas/:id/versions/:version/options returns success map", %{
    conn: conn
  } do
    conn = get(conn, "/api/json/builder_contract/schemas/jsonapi-v1/versions/v1/options?builder=alert")
    body = json_response(conn, 200)

    assert %{"status" => "ok", "payload" => payload} = body
    assert payload["schema_id"] == "jsonapi-v1"
  end

  test "GET /api/json/builder_contract/schemas/:id/versions/:version/options returns error map", %{
    conn: conn
  } do
    conn = get(conn, "/api/json/builder_contract/schemas/missing/versions/v1/options?builder=alert")
    body = json_response(conn, 200)

    assert %{"status" => "error", "reason" => "not_found"} = body
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
end
