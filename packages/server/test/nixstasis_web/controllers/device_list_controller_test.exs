defmodule NixstasisWeb.DeviceListControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices

  setup do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)
    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    {:ok, allowed} = Devices.create_device(%{mac_address: "12:34:56:78:AB:01", product_name: "allowed"})
    {:ok, blocked} = Devices.create_device(%{mac_address: "12:34:56:78:AB:02", product_name: "blocked"})
    %{allowed: allowed, blocked: blocked}
  end

  test "requires verified operator authentication", %{conn: conn} do
    assert response(get(conn, "/api/v1/devices"), 401) == ""

    conn =
      conn
      |> recycle()
      |> put_req_header("x-token-user-roles", "nixstasis/admin")
      |> get("/api/v1/devices")

    assert response(conn, 401) == ""
  end

  test "unscoped viewers retain fleet access", %{conn: conn, allowed: allowed, blocked: blocked} do
    body = conn |> viewer() |> get("/api/v1/devices") |> json_response(200)
    assert MapSet.new(Enum.map(body["data"], & &1["id"])) == MapSet.new([allowed.id, blocked.id])
  end

  test "forwarded device scope headers neither restrict nor reject the list", %{
    conn: conn,
    allowed: allowed,
    blocked: blocked
  } do
    for scope <- [allowed.id, "", "not-a-uuid"] do
      body =
        conn
        |> recycle()
        |> viewer()
        |> put_req_header("x-token-device-ids", scope)
        |> get("/api/v1/devices")
        |> json_response(200)

      assert MapSet.new(Enum.map(body["data"], & &1["id"])) == MapSet.new([allowed.id, blocked.id])
    end
  end

  test "explicit local development fallback still works", %{conn: conn} do
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, true)
    assert length(json_response(get(conn, "/api/v1/devices"), 200)["data"]) == 2
  end

  # Add viewer claims and the test proxy credential; callers can add a device
  # scope separately to exercise scoped versus unrestricted list behavior.
  defp viewer(conn) do
    conn
    |> put_req_header("x-token-user-roles", "nixstasis/viewer")
    |> put_trusted_proxy_auth()
  end
end
