defmodule NixstasisWeb.DeviceControllerTest do
  use NixstasisWeb.ConnCase

  test "POST /api/v1/devices/register registers a new device", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:FF",
      "product_key" => "prod_123",
      "schema_definition" => %{"temp" => "float"},
      "metadata" => %{"fw" => "1.0"}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert %{"id" => _id, "approval_status" => "pending"} = json_response(conn, 201)["data"]
  end
end
