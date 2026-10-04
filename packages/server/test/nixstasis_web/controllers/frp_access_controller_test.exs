defmodule NixstasisWeb.FrpAccessControllerTest do
  use NixstasisWeb.ConnCase, async: true

  alias Nixstasis.Devices.FrpsToken

  @base_domain "devices.example.com"

  test "unscoped operators can access device-owned HTTP tunnel hosts", %{conn: conn} do
    device_id = Ecto.UUID.generate()

    conn = authorize_request(conn, "nixstasis/operator", device_host(device_id))
    assert response(conn, 204) == ""

    conn =
      conn
      |> recycle()
      |> authorize_request("nixstasis/operator", device_host(device_id, "console"))

    assert response(conn, 204) == ""
  end

  test "viewers cannot consume active device HTTP tunnels", %{conn: conn} do
    device_id = Ecto.UUID.generate()

    conn = authorize_request(conn, "nixstasis/viewer", device_host(device_id))
    assert response(conn, 403) == ""
  end

  test "scoped operators can access only their authorized device", %{conn: conn} do
    allowed_device_id = Ecto.UUID.generate()
    blocked_device_id = Ecto.UUID.generate()

    conn =
      authorize_request(
        conn,
        "nixstasis/operator",
        device_host(allowed_device_id),
        [allowed_device_id]
      )

    assert response(conn, 204) == ""

    conn =
      conn
      |> recycle()
      |> authorize_request(
        "nixstasis/operator",
        device_host(blocked_device_id),
        [allowed_device_id]
      )

    assert response(conn, 403) == ""
  end

  test "an explicit empty device scope denies all tunnel access", %{conn: conn} do
    device_id = Ecto.UUID.generate()

    conn = authorize_request(conn, "nixstasis/operator", device_host(device_id), [])
    assert response(conn, 403) == ""
  end

  test "forged operator claims without the Caddy proxy credential are rejected", %{conn: conn} do
    device_id = Ecto.UUID.generate()

    conn =
      conn
      |> put_req_header("x-token-user-roles", "nixstasis/admin")
      |> put_req_header("x-nixstasis-requested-host", device_host(device_id))
      |> get("/internal/frp/access")

    assert response(conn, 403) == ""
  end

  test "non-device and malformed FRP hosts are rejected", %{conn: conn} do
    invalid_hosts = [
      "frp-admin.#{@base_domain}",
      "atom-not-a-uuid.#{@base_domain}",
      "atom-#{String.duplicate("a", 32)}suffix.#{@base_domain}",
      "atom-#{String.duplicate("a", 32)}-.#{@base_domain}",
      "atom-#{String.duplicate("a", 32)}.other.example.com"
    ]

    for host <- invalid_hosts do
      checked_conn =
        conn
        |> recycle()
        |> authorize_request("nixstasis/admin", host)

      assert response(checked_conn, 403) == ""
    end
  end

  defp authorize_request(conn, role, host, device_ids \\ nil) do
    conn =
      conn
      |> put_req_header("x-token-user-roles", role)
      |> put_req_header("x-nixstasis-requested-host", host)
      |> put_trusted_proxy_auth()

    conn =
      case device_ids do
        nil -> conn
        ids -> put_req_header(conn, "x-token-device-ids", Enum.join(ids, ","))
      end

    get(conn, "/internal/frp/access")
  end

  defp device_host(device_id, route_name \\ nil) do
    name = FrpsToken.device_name(device_id)
    name = if is_binary(route_name), do: name <> "-" <> route_name, else: name
    name <> "." <> @base_domain
  end
end
