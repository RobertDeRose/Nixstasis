defmodule NixstasisWeb.Plugs.DevicePermissionsTest do
  use NixstasisWeb.ConnCase, async: true

  alias NixstasisWeb.Plugs.DevicePermissions

  test "uses local development defaults when AuthCrunch headers are absent", %{conn: conn} do
    conn = conn |> init_test_session(%{}) |> DevicePermissions.call([])

    assert get_session(conn, "device_permissions") == %{
             "can_view" => true,
             "can_manage" => true,
             "can_remote_access" => true
           }

    assert is_nil(get_session(conn, "report_permissions"))
  end

  test "maps AuthCrunch viewer role to read-only permissions", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> put_req_header("x-token-user-email", "viewer@example.com")
      |> init_test_session(%{})
      |> DevicePermissions.call([])

    assert get_session(conn, "device_permissions") == %{
             "can_view" => true,
             "can_manage" => false,
             "can_remote_access" => false
           }

    assert get_session(conn, "report_permissions") == %{"can_view" => true, "can_manage" => false}
    assert get_session(conn, "operator_context")["email"] == "viewer@example.com"
  end

  test "fails closed when production AuthCrunch claims are malformed", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-token-user-email", "viewer@example.com")
      |> init_test_session(%{})
      |> DevicePermissions.call([])

    assert get_session(conn, "device_permissions") == %{
             "can_view" => false,
             "can_manage" => false,
             "can_remote_access" => false
           }

    assert get_session(conn, "report_permissions") == %{"can_view" => false, "can_manage" => false}
    assert get_session(conn, "operator_context") == %{"authcrunch_claim_error" => true}
  end
end
