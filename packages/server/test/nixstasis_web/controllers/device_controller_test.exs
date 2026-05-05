defmodule NixstasisWeb.DeviceControllerTest do
  use NixstasisWeb.ConnCase
  alias Nixstasis.Devices

  test "POST /api/v1/devices/register registers a new device", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:FF",
      "product_name" => "prod_123",
      "schema" => %{
        "product" => "prod_123",
        "type" => "object",
        "properties" => %{"temp" => %{"type" => "number"}}
      },
      "metadata" => %{"fw" => "1.0"}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert %{"id" => _id, "approval_status" => "pending"} = json_response(conn, 201)["data"]
  end

  test "GET /api/v1/devices filters by product/account/approval status", %{conn: conn} do
    {:ok, _} =
      Devices.create_device(%{
        mac_address: "11:11:11:11:11:11",
        product_name: "Alpha",
        account_number: "11111",
        approval_status: :pending
      })

    {:ok, _} =
      Devices.create_device(%{
        mac_address: "22:22:22:22:22:22",
        product_name: "Beta",
        account_number: "22222",
        approval_status: :approved
      })

    conn = get(conn, ~p"/api/v1/devices?product=Alpha&account_number=11111&approval_status=pending")
    body = json_response(conn, 200)

    assert length(body["data"]) == 1
    assert hd(body["data"])["mac_address"] == "11:11:11:11:11:11"
    assert body["meta"]["active_filters"]["product"] == "Alpha"
    assert body["meta"]["active_filters"]["approval_status"] == "pending"
  end

  test "POST /api/v1/devices/register rejects schema missing product", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:F1",
      "product_name" => "prod_123",
      "schema" => %{"type" => "object", "properties" => %{}}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert json_response(conn, 422)["errors"]["detail"]
  end

  test "POST /api/v1/devices/register rejects missing schema", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:F2",
      "product_name" => "prod_123"
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert json_response(conn, 422)["errors"]["detail"] =~ "product"
  end

  test "POST /api/v1/devices/register rejects empty schema_definition", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:F3",
      "product_name" => "prod_123",
      "schema_definition" => %{}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert json_response(conn, 422)["errors"]["detail"] =~ "product"
  end

  test "GET /api/v1/devices filters by connectivity status", %{conn: conn} do
    {:ok, _} =
      Devices.create_device(%{
        mac_address: "55:55:55:55:55:55",
        product_name: "Alpha",
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _} =
      Devices.create_device(%{
        mac_address: "66:66:66:66:66:66",
        product_name: "Beta",
        last_seen_at: DateTime.add(DateTime.utc_now(), -10, :minute)
      })

    conn = get(conn, ~p"/api/v1/devices?connectivity_status=offline")
    body = json_response(conn, 200)

    assert length(body["data"]) == 1
    assert hd(body["data"])["mac_address"] == "66:66:66:66:66:66"
    assert body["meta"]["active_filters"]["connectivity_status"] == "offline"
  end

  test "POST /api/v1/devices/:device_id/modal is obsolete", %{conn: conn} do
    {:ok, device} =
      Devices.create_device(%{
        mac_address: "33:33:33:33:33:33",
        product_name: "Alpha"
      })

    conn = post(conn, "/api/v1/devices/#{device.id}/modal")
    assert response(conn, 404)
    assert Devices.get_device!(device.id).remote_access_requested == false
  end

  test "DELETE /api/v1/devices/:device_id/modal is obsolete", %{conn: conn} do
    {:ok, device} =
      Devices.create_device(%{
        mac_address: "44:44:44:44:44:44",
        product_name: "Alpha",
        remote_access_requested: true
      })

    conn = delete(conn, "/api/v1/devices/#{device.id}/modal")
    assert response(conn, 404)
    assert Devices.get_device!(device.id).remote_access_requested == true
  end
end
