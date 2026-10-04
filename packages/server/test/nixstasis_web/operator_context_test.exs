defmodule NixstasisWeb.OperatorContextTest do
  use NixstasisWeb.ConnCase, async: false

  alias NixstasisWeb.OperatorContext

  test "maps viewer role from an authenticated proxy to read-only permissions", %{conn: conn} do
    assert {:ok, context} =
             conn
             |> put_req_header("x-token-user-roles", "nixstasis/viewer")
             |> put_trusted_proxy_auth()
             |> OperatorContext.from_conn()

    assert context["roles"] == ["nixstasis/viewer"]
    assert context["device_permissions"] == %{"can_view" => true, "can_manage" => false, "can_remote_access" => false}
    assert context["report_permissions"] == %{"can_view" => true, "can_manage" => false}
    assert context["settings_permissions"] == %{"can_manage" => false}

    assert context["command_policy_permissions"] == %{
             "can_view_status" => true,
             "can_view_details" => false,
             "can_manage" => false
           }
  end

  test "maps operator role to remote access and report management", %{conn: conn} do
    assert {:ok, context} =
             conn
             |> put_req_header("x-token-user-roles", "nixstasis/operator")
             |> put_trusted_proxy_auth()
             |> OperatorContext.from_conn()

    assert context["device_permissions"] == %{"can_view" => true, "can_manage" => true, "can_remote_access" => true}
    assert context["report_permissions"] == %{"can_view" => true, "can_manage" => true}
    assert context["settings_permissions"] == %{"can_manage" => false}

    assert context["command_policy_permissions"] == %{
             "can_view_status" => true,
             "can_view_details" => true,
             "can_manage" => true
           }
  end

  test "normalizes space and comma separated role claims", %{conn: conn} do
    assert {:ok, context} =
             conn
             |> put_req_header("x-token-user-roles", "nixstasis/viewer nixstasis/OPERATOR,nixstasis/admin")
             |> put_trusted_proxy_auth()
             |> OperatorContext.from_conn()

    assert context["roles"] == ["nixstasis/viewer", "nixstasis/operator", "nixstasis/admin"]
    assert context["device_permissions"]["can_remote_access"] == true
    assert context["settings_permissions"] == %{"can_manage" => true}
  end

  test "merges mixed roles with maximum privileges regardless of order", %{conn: conn} do
    assert {:ok, context} =
             conn
             |> put_req_header("x-token-user-roles", "nixstasis/operator nixstasis/viewer")
             |> put_trusted_proxy_auth()
             |> OperatorContext.from_conn()

    assert context["device_permissions"] == %{
             "can_view" => true,
             "can_manage" => true,
             "can_remote_access" => true
           }

    assert context["report_permissions"] == %{"can_view" => true, "can_manage" => true}
  end

  test "applies forwarded device scope claims to device permissions", %{conn: conn} do
    assert {:ok, context} =
             conn
             |> put_req_header("x-token-user-roles", "nixstasis/operator")
             |> put_req_header("x-token-device-ids", "device-a,device-b")
             |> put_trusted_proxy_auth()
             |> OperatorContext.from_conn()

    assert context["device_permissions"] == %{
             "can_view" => true,
             "can_manage" => true,
             "can_remote_access" => true,
             "device_ids" => ["device-a", "device-b"]
           }
  end

  test "rejects forged AuthCrunch claims without proxy authentication", %{conn: conn} do
    assert :error =
             conn
             |> put_req_header("x-token-user-roles", "nixstasis/admin")
             |> OperatorContext.from_conn()
  end

  test "rejects AuthCrunch claims with the wrong proxy credential", %{conn: conn} do
    assert :error =
             conn
             |> put_req_header("x-token-user-roles", "nixstasis/admin")
             |> put_req_header("x-nixstasis-proxy-token", String.duplicate("x", 32))
             |> OperatorContext.from_conn()
  end

  test "fails closed for missing or unknown production roles", %{conn: conn} do
    assert :error =
             conn
             |> put_req_header("x-token-user-email", "user@example.com")
             |> put_trusted_proxy_auth()
             |> OperatorContext.from_conn()

    assert :error =
             conn
             |> recycle()
             |> put_req_header("x-token-user-roles", "guest")
             |> put_trusted_proxy_auth()
             |> OperatorContext.from_conn()
  end

  test "detects local development requests when no AuthCrunch claim headers exist", %{conn: conn} do
    assert :local_development = OperatorContext.from_conn(conn)
  end

  test "fails closed for requests without AuthCrunch claim headers when fallback is disabled", %{conn: conn} do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    assert :error = OperatorContext.from_conn(conn)
  end
end
