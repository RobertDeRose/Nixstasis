defmodule NixstasisWeb.TLSControllerTest do
  use NixstasisWeb.ConnCase, async: false

  alias Nixstasis.Devices

  setup do
    original_base_domain = Application.get_env(:nixstasis, :base_domain)
    Application.put_env(:nixstasis, :base_domain, "devices.example.com")

    on_exit(fn ->
      if original_base_domain do
        Application.put_env(:nixstasis, :base_domain, original_base_domain)
      else
        Application.delete_env(:nixstasis, :base_domain)
      end
    end)

    :ok
  end

  test "approves reserved hosts", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/check_domain?domain=auth.devices.example.com")

    assert response(conn, 204) == ""
  end

  test "approves device hosts only when remote access is requested", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:DD:EE:FF",
        product_name: "P1",
        remote_access_requested: true
      })

    conn = get(conn, ~p"/api/v1/check_domain?domain=atom-aabbccddeeff.devices.example.com")

    assert response(conn, 204) == ""
  end

  test "denies unknown or inactive device hosts", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        mac_address: "11:22:33:44:55:66",
        product_name: "P1",
        remote_access_requested: false
      })

    conn = get(conn, ~p"/api/v1/check_domain?domain=atom-112233445566.devices.example.com")

    assert %{"error" => "The host is not permitted"} = json_response(conn, 401)
  end
end
