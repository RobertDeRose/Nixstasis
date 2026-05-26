defmodule NixstasisWeb.OperatorContextTest do
  use NixstasisWeb.ConnCase, async: true

  alias NixstasisWeb.OperatorContext

  test "maps viewer role to read-only device and report permissions" do
    assert {:ok, context} = OperatorContext.from_headers(%{"x-token-user-roles" => "viewer"})

    assert context["roles"] == ["viewer"]
    assert context["device_permissions"] == %{"can_view" => true, "can_remote_access" => false}
    assert context["report_permissions"] == %{"can_view" => true, "can_manage" => false}
  end

  test "maps operator role to remote access and report management" do
    assert {:ok, context} = OperatorContext.from_headers(%{"x-token-user-roles" => "operator"})

    assert context["device_permissions"] == %{"can_view" => true, "can_remote_access" => true}
    assert context["report_permissions"] == %{"can_view" => true, "can_manage" => true}
  end

  test "normalizes space and comma separated role claims" do
    assert {:ok, context} = OperatorContext.from_headers(%{"x-token-user-roles" => "Viewer, OPERATOR admin"})

    assert context["roles"] == ["viewer", "operator", "admin"]
    assert context["device_permissions"]["can_remote_access"] == true
  end

  test "fails closed for missing or unknown production roles" do
    assert :error = OperatorContext.from_headers(%{"x-token-user-email" => "user@example.com"})
    assert :error = OperatorContext.from_headers(%{"x-token-user-roles" => "guest"})
  end

  test "detects local development requests when no AuthCrunch claim headers exist", %{conn: conn} do
    assert :local_development = OperatorContext.from_conn(conn)
  end
end
