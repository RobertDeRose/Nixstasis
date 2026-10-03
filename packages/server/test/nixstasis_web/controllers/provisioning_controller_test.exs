defmodule NixstasisWeb.ProvisioningControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices

  test "requires the operator permission boundary before reading an artifact", %{conn: conn} do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    conn =
      conn
      |> put_req_header("content-type", "application/octet-stream")
      |> post("/api/v1/provisioning/devices/#{Ecto.UUID.generate()}", "config = true\n")

    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
  end

  test "rejects an unapproved device without opening remote access", %{conn: conn} do
    {:ok, device} =
      Devices.create_device(%{
        mac_address: "AA:BB:CC:DD:EE:21",
        product_name: "atom-bootstrap",
        approval_status: :pending,
        last_seen_at: DateTime.utc_now()
      })

    conn =
      conn
      |> put_req_header("content-type", "application/octet-stream")
      |> post("/api/v1/provisioning/devices/#{device.id}", "config = true\n")

    assert %{"error" => %{"code" => "device_not_approved"}} = json_response(conn, 422)
    refute Devices.get_device!(device.id).remote_access_requested
  end

  test "requires the exact artifact content type", %{conn: conn} do
    conn = post(conn, "/api/v1/provisioning/devices/#{Ecto.UUID.generate()}", %{"config" => "true"})

    assert %{"error" => %{"code" => "unsupported_content_type"}} = json_response(conn, 415)
  end
end
