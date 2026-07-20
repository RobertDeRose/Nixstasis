defmodule NixstasisWeb.OperatorContextTest do
  use NixstasisWeb.ConnCase, async: false

  alias NixstasisWeb.OperatorContext

  test "maps viewer role to read-only device and report permissions" do
    assert {:ok, context} = OperatorContext.from_headers(%{"x-token-user-roles" => "nixstasis/viewer"})

    assert context["roles"] == ["nixstasis/viewer"]
    assert context["device_permissions"] == %{"can_view" => true, "can_manage" => false, "can_remote_access" => false}
    assert context["report_permissions"] == %{"can_view" => true, "can_manage" => false}

    assert context["command_policy_permissions"] == %{
             "can_view_status" => true,
             "can_view_details" => false,
             "can_manage" => false
           }
  end

  test "maps operator role to remote access and report management" do
    assert {:ok, context} = OperatorContext.from_headers(%{"x-token-user-roles" => "nixstasis/operator"})

    assert context["device_permissions"] == %{"can_view" => true, "can_manage" => true, "can_remote_access" => true}
    assert context["report_permissions"] == %{"can_view" => true, "can_manage" => true}

    assert context["command_policy_permissions"] == %{
             "can_view_status" => true,
             "can_view_details" => true,
             "can_manage" => true
           }
  end

  test "normalizes space and comma separated role claims" do
    assert {:ok, context} =
             OperatorContext.from_headers(%{
               "x-token-user-roles" => "nixstasis/viewer nixstasis/OPERATOR,nixstasis/admin"
             })

    assert context["roles"] == ["nixstasis/viewer", "nixstasis/operator", "nixstasis/admin"]
    assert context["device_permissions"]["can_remote_access"] == true
  end

  test "merges mixed roles with maximum privileges regardless of order" do
    assert {:ok, context} =
             OperatorContext.from_headers(%{
               "x-token-user-roles" => "nixstasis/operator nixstasis/viewer"
             })

    assert context["device_permissions"] == %{
             "can_view" => true,
             "can_manage" => true,
             "can_remote_access" => true
           }

    assert context["report_permissions"] == %{"can_view" => true, "can_manage" => true}
  end

  test "applies forwarded device scope claims to device permissions" do
    assert {:ok, context} =
             OperatorContext.from_headers(%{
               "x-token-user-roles" => "nixstasis/operator",
               "x-token-device-ids" => "device-a,device-b"
             })

    assert context["device_permissions"] == %{
             "can_view" => true,
             "can_manage" => true,
             "can_remote_access" => true,
             "device_ids" => ["device-a", "device-b"]
           }
  end

  test "fails closed for missing or unknown production roles" do
    assert :error = OperatorContext.from_headers(%{"x-token-user-email" => "user@example.com"})
    assert :error = OperatorContext.from_headers(%{"x-token-user-roles" => "guest"})
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
