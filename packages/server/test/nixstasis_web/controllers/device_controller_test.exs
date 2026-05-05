defmodule NixstasisWeb.DeviceControllerTest do
  use NixstasisWeb.ConnCase
  alias Nixstasis.Devices

  test "POST /api/v1/devices/register registers a new device", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:FF",
      "product_name" => "prod_123",
      "schema" => %{"temp" => "float"},
      "metadata" => %{"fw" => "1.0"}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert %{"id" => _id, "approval_status" => "pending"} = json_response(conn, 201)["data"]
  end

  test "GET /api/v1/devices filters by product/account/status", %{conn: conn} do
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

    conn = get(conn, ~p"/api/v1/devices?product=Alpha&account_number=11111&status=pending")
    body = json_response(conn, 200)

    assert length(body["data"]) == 1
    assert hd(body["data"])["mac_address"] == "11:11:11:11:11:11"
    assert body["meta"]["active_filters"]["product"] == "Alpha"
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
